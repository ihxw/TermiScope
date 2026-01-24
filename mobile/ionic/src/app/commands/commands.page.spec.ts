import { ComponentFixture, TestBed } from '@angular/core/testing';
import { CommandsPage } from './commands.page';

describe('CommandsPage', () => {
  let component: CommandsPage;
  let fixture: ComponentFixture<CommandsPage>;

  beforeEach(() => {
    fixture = TestBed.createComponent(CommandsPage);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
