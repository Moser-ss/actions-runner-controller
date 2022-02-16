package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
)

const (
	rEnterprise   = "enterprise"
	rOrganization = "organization"
	rRepository   = "repository"
)

var (
	runnersMetrics = []prometheus.Collector{
		runners,
	}
)

var (
	runners = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "runners",
			Help: "total number of runners",
		},
		[]string{rEnterprise, rOrganization, rRepository},
	)
)

func SetRunners(numRunners int, enterprise, organization, repository string) {
	labels := prometheus.Labels{
		rEnterprise:   enterprise,
		rOrganization: organization,
		rRepository:   repository,
	}
	runners.With(labels).Set(float64(numRunners))
}
