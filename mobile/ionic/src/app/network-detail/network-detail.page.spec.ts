import { ComponentFixture, TestBed } from '@angular/core/testing';
import { NetworkDetailPage } from './network-detail.page';

describe('NetworkDetailPage', () => {
  let component: NetworkDetailPage;
  let fixture: ComponentFixture<NetworkDetailPage>;

  beforeEach(() => {
    fixture = TestBed.createComponent(NetworkDetailPage);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
