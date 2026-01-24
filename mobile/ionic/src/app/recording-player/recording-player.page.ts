import { Component, OnInit, OnDestroy, ViewChild, ElementRef, AfterViewInit } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { RecordingService } from '../services/recording.service';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { ToastController, LoadingController } from '@ionic/angular';

@Component({
  selector: 'app-recording-player',
  templateUrl: './recording-player.page.html',
  styleUrls: ['./recording-player.page.scss'],
  standalone: false
})
export class RecordingPlayerPage implements OnInit, OnDestroy, AfterViewInit {
  @ViewChild('terminalContainer', { static: false }) terminalContainer!: ElementRef;

  id: string | null = null;
  term: Terminal | null = null;
  fitAddon: FitAddon | null = null;
  events: any[] = [];
  isPlaying = false;
  isPaused = false;
  progress = 0; // 0-100 placeholder

  private abortController = new AbortController();

  constructor(
    private route: ActivatedRoute,
    private recordingService: RecordingService,
    private toastCtrl: ToastController,
    private loadingCtrl: LoadingController
  ) { }

  ngOnInit() {
    this.id = this.route.snapshot.queryParamMap.get('id');
  }

  ngAfterViewInit() {
    this.initTerminal();
    if (this.id) {
      this.loadRecording();
    }
  }

  ngOnDestroy() {
    this.stop();
    if (this.term) {
      this.term.dispose();
    }
  }

  async loadRecording() {
    const loading = await this.loadingCtrl.create({ message: '加载录像...' });
    await loading.present();
    try {
      const text: any = await this.recordingService.getStream(this.id!);
      // Parse JSONL
      // Each line is [time, type, data]
      // time is float seconds relative to start

      const lines = text.split('\n');
      this.events = [];
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const evt = JSON.parse(line);
          if (Array.isArray(evt) && evt.length >= 3) {
            this.events.push({
              time: evt[0],
              type: evt[1],
              data: evt[2]
            });
          }
        } catch (e) { }
      }

      this.play();
    } catch (e) {
      this.showToast('无法加载录像');
    } finally {
      loading.dismiss();
    }
  }

  initTerminal() {
    this.term = new Terminal({
      cursorBlink: false,
      fontSize: 12,
      fontFamily: 'monospace',
      theme: {
        background: '#1e1e1e',
        foreground: '#ffffff'
      },
      disableStdin: true
    });
    this.fitAddon = new FitAddon();
    this.term.loadAddon(this.fitAddon);
    this.term.open(this.terminalContainer.nativeElement);
    setTimeout(() => this.fitAddon!.fit(), 100);
  }

  async play() {
    this.isPlaying = true;
    this.isPaused = false;
    this.term?.reset();

    let startTime = Date.now();
    let eventIndex = 0;

    // Very simple replay loop
    const process = async () => {
      if (!this.isPlaying || this.isPaused) return;
      // Check if finished
      if (eventIndex >= this.events.length) {
        this.isPlaying = false;
        return;
      }

      const evt = this.events[eventIndex];
      // Check time
      // evt.time is offset in seconds.
      // We can just sleep until next event?
      // Or efficient loop.

      if (evt.type === 'o') { // stdout
        this.term?.write(evt.data);
      }

      eventIndex++;
      // Calculate delay to next event
      if (eventIndex < this.events.length) {
        const nextEvt = this.events[eventIndex];
        const delay = (nextEvt.time - evt.time) * 1000;
        if (delay > 0) {
          // Cap delay to avoid long pauses?
          await new Promise(r => setTimeout(r, delay));
        }
      }

      if (this.isPlaying && !this.isPaused) {
        process(); // Recursion but with await creates microtask loop, stack safe? 
        // Better use setTimeout to avoid stack overflow if delay is 0.
        // Or while loop with sleep.
      }
    };

    // Better implementation using While loop
    this.replayLoop();
  }

  async replayLoop() {
    let start = 0;
    // Actually we need to respect the time diffs.
    // We can iterate events.
    for (let i = 0; i < this.events.length; i++) {
      if (!this.isPlaying) break;
      // if paused, wait
      while (this.isPaused) {
        await new Promise(r => setTimeout(r, 100));
        if (!this.isPlaying) break;
      }

      const evt = this.events[i];
      if (evt.type === 'o') {
        this.term?.write(evt.data);
      }

      // Wait for next
      if (i < this.events.length - 1) {
        const next = this.events[i + 1];
        const delay = (next.time - evt.time) * 1000;
        if (delay > 0) {
          await new Promise(r => setTimeout(r, delay));
        }
      }
    }
    this.isPlaying = false;
  }

  stop() {
    this.isPlaying = false;
  }

  pause() {
    this.isPaused = !this.isPaused;
  }

  restart() {
    this.stop();
    setTimeout(() => this.play(), 100);
  }

  async showToast(msg: string) {
    const toast = await this.toastCtrl.create({ message: msg, duration: 2000 });
    toast.present();
  }
}
