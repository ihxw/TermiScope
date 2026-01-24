import { ComponentFixture, TestBed } from '@angular/core/testing';
import { SftpBrowserPage } from './sftp-browser.page';

describe('SftpBrowserPage', () => {
  let component: SftpBrowserPage;
  let fixture: ComponentFixture<SftpBrowserPage>;

  beforeEach(() => {
    fixture = TestBed.createComponent(SftpBrowserPage);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
