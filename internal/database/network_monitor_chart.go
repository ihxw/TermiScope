package database

import (
	"time"

	"github.com/ihxw/termiscope/internal/models"
)

// ChartDisplayMaxPoints is the max points returned per task for latency charts.
const ChartDisplayMaxPoints = 1500

// NetworkLatencyRollupSampleCount is the number of adjacent raw checks folded into one chart point.
const NetworkLatencyRollupSampleCount = 2

// DownsampleNetworkResults reduces points for chart rendering while preserving shape.
// Uses time-bucket averaging when over the cap; preserves order (ascending by created_at).
func DownsampleNetworkResults(results []models.NetworkMonitorResult, maxPoints int) []models.NetworkMonitorResult {
	if maxPoints <= 0 || len(results) <= maxPoints {
		return results
	}

	n := len(results)
	bucketSize := (n + maxPoints - 1) / maxPoints
	out := make([]models.NetworkMonitorResult, 0, maxPoints)

	for i := 0; i < n; i += bucketSize {
		end := i + bucketSize
		if end > n {
			end = n
		}
		bucket := results[i:end]
		agg := aggregateBucket(bucket)
		out = append(out, agg)
	}
	return out
}

// RollupNetworkResults folds adjacent raw checks into sample windows before charting.
// It avoids joining windows across long collection gaps so outages or paused tasks stay visible.
func RollupNetworkResults(results []models.NetworkMonitorResult, sampleCount int, maxGap time.Duration) []models.NetworkMonitorResult {
	if sampleCount <= 1 || len(results) <= 1 {
		return results
	}

	out := make([]models.NetworkMonitorResult, 0, (len(results)+sampleCount-1)/sampleCount)
	bucket := make([]models.NetworkMonitorResult, 0, sampleCount)
	flush := func() {
		if len(bucket) == 0 {
			return
		}
		agg := aggregateLatencyBucket(bucket)
		agg.CreatedAt = bucket[len(bucket)-1].CreatedAt
		out = append(out, agg)
		bucket = bucket[:0]
	}

	for _, r := range results {
		if len(bucket) > 0 && maxGap > 0 && r.CreatedAt.Sub(bucket[len(bucket)-1].CreatedAt) > maxGap {
			flush()
		}
		bucket = append(bucket, r)
		if len(bucket) == sampleCount {
			flush()
		}
	}
	flush()
	return out
}

func aggregateBucket(bucket []models.NetworkMonitorResult) models.NetworkMonitorResult {
	if len(bucket) == 1 {
		return bucket[0]
	}

	agg := aggregateLatencyBucket(bucket)
	// Use midpoint timestamp for smoother x-axis placement when display downsampling.
	mid := len(bucket) / 2
	agg.CreatedAt = bucket[mid].CreatedAt
	return agg
}

func aggregateLatencyBucket(bucket []models.NetworkMonitorResult) models.NetworkMonitorResult {
	if len(bucket) == 1 {
		return bucket[0]
	}

	var sumLatency float64
	var successCount int
	var latencyCount int
	var sumPacketLoss float64
	var last models.NetworkMonitorResult

	for _, r := range bucket {
		last = r
		if r.Success {
			successCount++
			if r.Latency >= 0 {
				sumLatency += r.Latency
				latencyCount++
			}
			sumPacketLoss += r.PacketLoss
		} else if r.PacketLoss > 0 {
			sumPacketLoss += r.PacketLoss
		} else {
			sumPacketLoss += 100
		}
	}

	agg := last
	agg.PacketLoss = sumPacketLoss / float64(len(bucket))
	if successCount*2 >= len(bucket) && latencyCount > 0 {
		agg.Latency = sumLatency / float64(latencyCount)
		agg.Success = true
	} else {
		agg.Success = false
		agg.Latency = -1
	}
	return agg
}
