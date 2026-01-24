import { ComponentFixture, TestBed } from '@angular/core/testing';
import { NetworkMonitorPage } from './network-monitor.page';

describe('NetworkMonitorPage', () => {
  let component: NetworkMonitorPage;
  let fixture: ComponentFixture<NetworkMonitorPage>;

  beforeEach(() => {
    fixture = TestBed.createComponent(NetworkMonitorPage);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
