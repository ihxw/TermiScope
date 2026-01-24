import { ComponentFixture, TestBed } from '@angular/core/testing';
import { SystemSettingsPage } from './system-settings.page';

describe('SystemSettingsPage', () => {
  let component: SystemSettingsPage;
  let fixture: ComponentFixture<SystemSettingsPage>;

  beforeEach(() => {
    fixture = TestBed.createComponent(SystemSettingsPage);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
