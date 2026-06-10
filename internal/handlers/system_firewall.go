package handlers

import (
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/firewall"
	"github.com/ihxw/termiscope/internal/utils"
)

func (h *SystemHandler) firewallManager() firewall.Manager {
	return firewall.NewManager()
}

func (h *SystemHandler) requireFirewallAvailable(c *gin.Context) (firewall.Manager, bool) {
	mgr := h.firewallManager()
	status, err := mgr.Status()
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return nil, false
	}
	if !status.Available {
		code := http.StatusServiceUnavailable
		if !status.Privileged {
			code = http.StatusForbidden
		}
		msg := status.Message
		if msg == "" {
			msg = "firewall management is unavailable"
		}
		utils.ErrorResponse(c, code, msg)
		return nil, false
	}
	return mgr, true
}

// GetFirewallStatus returns firewall availability and enabled state.
func (h *SystemHandler) GetFirewallStatus(c *gin.Context) {
	status, err := h.firewallManager().Status()
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, status)
}

// GetFirewallRules lists current firewall rules.
func (h *SystemHandler) GetFirewallRules(c *gin.Context) {
	rules, err := h.firewallManager().Rules()
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	if rules == nil {
		rules = []firewall.Rule{}
	}
	utils.SuccessResponse(c, http.StatusOK, rules)
}

// AddFirewallRule creates a new firewall rule.
func (h *SystemHandler) AddFirewallRule(c *gin.Context) {
	var req firewall.AddRuleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}
	mgr, ok := h.requireFirewallAvailable(c)
	if !ok {
		return
	}
	if err := mgr.AddRule(req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "rule added"})
}

// UpdateFirewallRule replaces an existing firewall rule by its display number.
func (h *SystemHandler) UpdateFirewallRule(c *gin.Context) {
	number, err := strconv.Atoi(c.Param("number"))
	if err != nil || number < 1 {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid rule number")
		return
	}
	var req firewall.AddRuleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}
	mgr, ok := h.requireFirewallAvailable(c)
	if !ok {
		return
	}
	if err := mgr.UpdateRule(number, req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "rule updated"})
}

// DeleteFirewallRule removes a firewall rule by its display number.
func (h *SystemHandler) DeleteFirewallRule(c *gin.Context) {
	number, err := strconv.Atoi(c.Param("number"))
	if err != nil || number < 1 {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid rule number")
		return
	}
	mgr, ok := h.requireFirewallAvailable(c)
	if !ok {
		return
	}
	if err := mgr.DeleteRule(number); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "rule deleted"})
}

// InitializeFirewall prepares the nftables table and imports rules without enabling DROP policy.
func (h *SystemHandler) InitializeFirewall(c *gin.Context) {
	mgr, ok := h.requireFirewallAvailable(c)
	if !ok {
		return
	}
	if err := mgr.Initialize(); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "firewall initialized"})
}

// GetFirewallKVMCompatibility reports KVM/libvirt coexistence status.
func (h *SystemHandler) GetFirewallKVMCompatibility(c *gin.Context) {
	status, err := h.firewallManager().KVMCompatibility()
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, status)
}

// ApplyFirewallKVMCompatibility installs libvirt-friendly nftables rules.
func (h *SystemHandler) ApplyFirewallKVMCompatibility(c *gin.Context) {
	mgr, ok := h.requireFirewallAvailable(c)
	if !ok {
		return
	}
	if err := mgr.EnsureKVMCompatibility(); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	status, err := mgr.KVMCompatibility()
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, status)
}

// GetFirewallExternalPorts lists ports with active public connections for enable confirmation.
func (h *SystemHandler) GetFirewallExternalPorts(c *gin.Context) {
	ports, err := h.firewallManager().ExternalAccessPorts(c.ClientIP())
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	if ports == nil {
		ports = []firewall.ExternalAccessPort{}
	}
	utils.SuccessResponse(c, http.StatusOK, ports)
}

// EnableFirewall turns the system firewall on.
func (h *SystemHandler) EnableFirewall(c *gin.Context) {
	var req firewall.EnableFirewallRequest
	if err := c.ShouldBindJSON(&req); err != nil && !errors.Is(err, io.EOF) {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}
	mgr, ok := h.requireFirewallAvailable(c)
	if !ok {
		return
	}
	if err := mgr.Enable(req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "firewall enabled"})
}

// DisableFirewall turns the system firewall off.
func (h *SystemHandler) DisableFirewall(c *gin.Context) {
	mgr, ok := h.requireFirewallAvailable(c)
	if !ok {
		return
	}
	if err := mgr.Disable(); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "firewall disabled"})
}

// GetFirewallPortForwards lists port forwarding rules.
func (h *SystemHandler) GetFirewallPortForwards(c *gin.Context) {
	rules, err := h.firewallManager().PortForwards()
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	if rules == nil {
		rules = []firewall.PortForwardRule{}
	}
	utils.SuccessResponse(c, http.StatusOK, rules)
}

// AddFirewallPortForward creates a port forwarding rule.
func (h *SystemHandler) AddFirewallPortForward(c *gin.Context) {
	var req firewall.AddPortForwardRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}
	mgr, ok := h.requireFirewallAvailable(c)
	if !ok {
		return
	}
	if err := mgr.AddPortForward(req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "port forward added"})
}

// UpdateFirewallPortForward replaces a port forwarding rule.
func (h *SystemHandler) UpdateFirewallPortForward(c *gin.Context) {
	number, err := strconv.Atoi(c.Param("number"))
	if err != nil || number < 1 {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid rule number")
		return
	}
	var req firewall.AddPortForwardRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}
	mgr, ok := h.requireFirewallAvailable(c)
	if !ok {
		return
	}
	if err := mgr.UpdatePortForward(number, req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "port forward updated"})
}

// DeleteFirewallPortForward removes a port forwarding rule.
func (h *SystemHandler) DeleteFirewallPortForward(c *gin.Context) {
	number, err := strconv.Atoi(c.Param("number"))
	if err != nil || number < 1 {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid rule number")
		return
	}
	mgr, ok := h.requireFirewallAvailable(c)
	if !ok {
		return
	}
	if err := mgr.DeletePortForward(number); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "port forward deleted"})
}

// GetFirewallPortForwardSettings returns port forwarding feature toggles.
func (h *SystemHandler) GetFirewallPortForwardSettings(c *gin.Context) {
	settings, err := h.firewallManager().GetPortForwardSettings()
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	utils.SuccessResponse(c, http.StatusOK, settings)
}

// UpdateFirewallPortForwardSettings updates port forwarding toggles.
func (h *SystemHandler) UpdateFirewallPortForwardSettings(c *gin.Context) {
	var req firewall.UpdatePortForwardSettingsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}
	mgr, ok := h.requireFirewallAvailable(c)
	if !ok {
		return
	}
	if err := mgr.UpdatePortForwardSettings(req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	settings, _ := mgr.GetPortForwardSettings()
	utils.SuccessResponse(c, http.StatusOK, settings)
}
