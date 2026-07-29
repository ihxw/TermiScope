package database

import (
	"time"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/gorm"
)

// TrafficHistoryPoint is one chart sample (bytes per second).
type TrafficHistoryPoint struct {
	Time   time.Time `json:"time"`
	RxRate uint64    `json:"rx_rate"`
	TxRate uint64    `json:"tx_rate"`
}

const maxMonitorRecordsFetch = 10080 // upper bound before SQL stride sampling

// QueryHostTrafficHistory loads monitor_records and derives per-interval rates.
func QueryHostTrafficHistory(db *gorm.DB, hostID uint, since time.Time) ([]TrafficHistoryPoint, error) {
	records, err := fetchMonitorRecordsForTraffic(db, hostID, since)
	if err != nil {
		return nil, err
	}
	points := deriveTrafficRates(records)
	return downsampleTrafficPoints(points, ChartDisplayMaxPoints), nil
}

func fetchMonitorRecordsForTraffic(db *gorm.DB, hostID uint, since time.Time) ([]models.MonitorRecord, error) {
	sinceUTC := since.UTC()
	var count int64
	if err := db.Model(&models.MonitorRecord{}).
		Where("host_id = ? AND created_at > ?", hostID, sinceUTC).
		Count(&count).Error; err != nil {
		return nil, err
	}

	records := make([]models.MonitorRecord, 0)
	if count <= int64(maxMonitorRecordsFetch) {
		err := db.Where("host_id = ? AND created_at > ?", hostID, sinceUTC).
			Order("created_at asc").
			Find(&records).Error
		return records, err
	}

	// Stride-sample in SQL so we do not load the full range into memory.
	step := int(count / maxMonitorRecordsFetch)
	if step < 2 {
		step = 2
	}
	err := db.Raw(`
SELECT * FROM monitor_records
WHERE host_id = ? AND created_at > ? AND id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (ORDER BY created_at ASC) AS rn
    FROM monitor_records
    WHERE host_id = ? AND created_at > ?
  ) WHERE rn = 1 OR (rn % ?) = 0
)
ORDER BY created_at ASC`,
		hostID, sinceUTC, hostID, sinceUTC, step,
	).Scan(&records).Error
	return records, err
}

func deriveTrafficRates(records []models.MonitorRecord) []TrafficHistoryPoint {
	if len(records) == 0 {
		return nil
	}
	out := make([]TrafficHistoryPoint, 0, len(records))

	for i := 1; i < len(records); i++ {
		prev := records[i-1]
		cur := records[i]
		sec := uint64(cur.CreatedAt.Sub(prev.CreatedAt).Seconds())
		if sec == 0 {
			continue
		}
		rxRate, txRate := trafficDeltaRates(prev.NetRx, prev.NetTx, cur.NetRx, cur.NetTx, sec)
		out = append(out, TrafficHistoryPoint{
			Time:   cur.CreatedAt,
			RxRate: rxRate,
			TxRate: txRate,
		})
	}
	return out
}

func trafficDeltaRates(prevRx, prevTx, curRx, curTx, sec uint64) (rxRate, txRate uint64) {
	if curRx >= prevRx {
		rxRate = (curRx - prevRx) / sec
	}
	if curTx >= prevTx {
		txRate = (curTx - prevTx) / sec
	}
	return rxRate, txRate
}

func downsampleTrafficPoints(points []TrafficHistoryPoint, maxPoints int) []TrafficHistoryPoint {
	if maxPoints <= 0 || len(points) <= maxPoints {
		return points
	}
	n := len(points)
	bucketSize := (n + maxPoints - 1) / maxPoints
	out := make([]TrafficHistoryPoint, 0, maxPoints)

	for i := 0; i < n; i += bucketSize {
		end := i + bucketSize
		if end > n {
			end = n
		}
		bucket := points[i:end]
		var sumRx, sumTx uint64
		for _, p := range bucket {
			sumRx += p.RxRate
			sumTx += p.TxRate
		}
		mid := len(bucket) / 2
		out = append(out, TrafficHistoryPoint{
			Time:   bucket[mid].Time,
			RxRate: sumRx / uint64(len(bucket)),
			TxRate: sumTx / uint64(len(bucket)),
		})
	}
	return out
}
