import { ComponentFixture, TestBed } from '@angular/core/testing';
import { RecordingsPage } from './recordings.page';

describe('RecordingsPage', () => {
  let component: RecordingsPage;
  let fixture: ComponentFixture<RecordingsPage>;

  beforeEach(() => {
    fixture = TestBed.createComponent(RecordingsPage);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
