package handlers

import (
	"strings"
	"testing"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	_ "modernc.org/sqlite"
)

func openNetworkTemplateTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsnName := strings.NewReplacer("/", "_", " ", "_").Replace(t.Name())
	db, err := gorm.Open(sqlite.Dialector{
		DriverName: "sqlite",
		DSN:        "file:" + dsnName + "?mode=memory&cache=shared&_time_format=sqlite",
	}, &gorm.Config{})
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	if err := db.AutoMigrate(
		&models.SSHHost{},
		&models.NetworkMonitorTemplate{},
		&models.NetworkMonitorTask{},
		&models.NetworkMonitorResult{},
	); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func createTemplateHost(t *testing.T, db *gorm.DB, userID uint, name string) models.SSHHost {
	t.Helper()
	host := models.SSHHost{
		UserID:   userID,
		Name:     name,
		Host:     "127.0.0.1",
		Username: "root",
		AuthType: "password",
		HostType: "control_monitor",
	}
	if err := db.Create(&host).Error; err != nil {
		t.Fatalf("create host: %v", err)
	}
	return host
}

func TestGetTemplateAssignedHostIDsIgnoresDeletedAndOtherUsers(t *testing.T) {
	db := openNetworkTemplateTestDB(t)

	tmpl := models.NetworkMonitorTemplate{Name: "Ping", Type: "ping", Target: "1.1.1.1", Frequency: 60}
	if err := db.Create(&tmpl).Error; err != nil {
		t.Fatalf("create template: %v", err)
	}
	active := createTemplateHost(t, db, 1, "active")
	deleted := createTemplateHost(t, db, 1, "deleted")
	otherUser := createTemplateHost(t, db, 2, "other")
	if err := db.Delete(&deleted).Error; err != nil {
		t.Fatalf("delete host: %v", err)
	}

	tasks := []models.NetworkMonitorTask{
		{HostID: active.ID, TemplateID: tmpl.ID, Type: "ping", Target: "1.1.1.1", Frequency: 60},
		{HostID: active.ID, TemplateID: tmpl.ID, Type: "ping", Target: "8.8.8.8", Frequency: 60},
		{HostID: deleted.ID, TemplateID: tmpl.ID, Type: "ping", Target: "1.1.1.1", Frequency: 60},
		{HostID: otherUser.ID, TemplateID: tmpl.ID, Type: "ping", Target: "1.1.1.1", Frequency: 60},
	}
	if err := db.Create(&tasks).Error; err != nil {
		t.Fatalf("create tasks: %v", err)
	}

	got, err := getTemplateAssignedHostIDs(db, tmpl.ID, 1)
	if err != nil {
		t.Fatalf("get assignments: %v", err)
	}
	if len(got) != 1 || got[0] != active.ID {
		t.Fatalf("got assignments %v, want only active host %d", got, active.ID)
	}
}

func TestSyncTemplateAssignmentsUnlinksDeselectedHosts(t *testing.T) {
	db := openNetworkTemplateTestDB(t)

	tmpl := models.NetworkMonitorTemplate{Name: "Ping", Type: "ping", Target: "1.1.1.1", Label: "Cloudflare", Frequency: 60}
	if err := db.Create(&tmpl).Error; err != nil {
		t.Fatalf("create template: %v", err)
	}
	first := createTemplateHost(t, db, 1, "first")
	second := createTemplateHost(t, db, 1, "second")
	otherUser := createTemplateHost(t, db, 2, "other")
	tasks := []models.NetworkMonitorTask{
		{HostID: first.ID, TemplateID: tmpl.ID, Type: "ping", Target: "1.1.1.1", Frequency: 60},
		{HostID: second.ID, TemplateID: tmpl.ID, Type: "ping", Target: "1.1.1.1", Frequency: 60},
		{HostID: otherUser.ID, TemplateID: tmpl.ID, Type: "ping", Target: "1.1.1.1", Frequency: 60},
	}
	if err := db.Create(&tasks).Error; err != nil {
		t.Fatalf("create tasks: %v", err)
	}

	if err := db.Transaction(func(tx *gorm.DB) error {
		return syncTemplateAssignments(tx, tmpl, 1, []uint{second.ID})
	}); err != nil {
		t.Fatalf("sync assignments: %v", err)
	}

	var firstTask, secondTask, otherTask models.NetworkMonitorTask
	if err := db.First(&firstTask, tasks[0].ID).Error; err != nil {
		t.Fatalf("load first task: %v", err)
	}
	if err := db.First(&secondTask, tasks[1].ID).Error; err != nil {
		t.Fatalf("load second task: %v", err)
	}
	if err := db.First(&otherTask, tasks[2].ID).Error; err != nil {
		t.Fatalf("load other task: %v", err)
	}
	if firstTask.TemplateID != 0 {
		t.Fatalf("first task template_id = %d, want 0", firstTask.TemplateID)
	}
	if secondTask.TemplateID != tmpl.ID {
		t.Fatalf("second task template_id = %d, want %d", secondTask.TemplateID, tmpl.ID)
	}
	if otherTask.TemplateID != tmpl.ID {
		t.Fatalf("other user task template_id = %d, want %d", otherTask.TemplateID, tmpl.ID)
	}
}
