package database

import "github.com/ihxw/termiscope/internal/models"

// ChartDisplayMaxPoints is the max points returned per task for latency charts.
const ChartDisplayMaxPoints = 1500

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

func aggregateBucket(bucket []models.NetworkMonitorResult) models.NetworkMonitorResult {
	if len(bucket) == 1 {
		return bucket[0]
	}

	var sumLatency float64
	var successCount int
	var last models.NetworkMonitorResult

	for _, r := range bucket {
		last = r
		if r.Success {
			sumLatency += r.Latency
			successCount++
		}
	}

	agg := last
	if successCount > 0 {
		agg.Latency = sumLatency / float64(successCount)
		agg.Success = true
		agg.PacketLoss = 0
	} else {
		agg.Success = false
		agg.Latency = 0
	}
	// Use midpoint timestamp for smoother x-axis placement
	mid := len(bucket) / 2
	agg.CreatedAt = bucket[mid].CreatedAt
	return agg
}
