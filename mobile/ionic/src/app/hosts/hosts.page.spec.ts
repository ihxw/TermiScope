import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HostsPage } from './hosts.page';

describe('HostsPage', () => {
  let component: HostsPage;
  let fixture: ComponentFixture<HostsPage>;

  beforeEach(() => {
    fixture = TestBed.createComponent(HostsPage);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
