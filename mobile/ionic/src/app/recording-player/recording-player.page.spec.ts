import { ComponentFixture, TestBed } from '@angular/core/testing';
import { RecordingPlayerPage } from './recording-player.page';

describe('RecordingPlayerPage', () => {
  let component: RecordingPlayerPage;
  let fixture: ComponentFixture<RecordingPlayerPage>;

  beforeEach(() => {
    fixture = TestBed.createComponent(RecordingPlayerPage);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
