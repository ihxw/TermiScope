import { ComponentFixture, TestBed } from '@angular/core/testing';
import { TerminalPage } from './terminal.page';

describe('TerminalPage', () => {
  let component: TerminalPage;
  let fixture: ComponentFixture<TerminalPage>;

  beforeEach(() => {
    fixture = TestBed.createComponent(TerminalPage);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
