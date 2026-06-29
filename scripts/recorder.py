import os
import time
import tkinter as tk
import numpy as np
import sounddevice as sd
import soundfile as sf

class AudioRecorder:
    def __init__(self, root):
        self.root = root
        self.root.title("ML Dataset Mono Recorder")
        self.is_recording = False
        self.audio_data = []
        self.samplerate = 48000
        self.stream = None

        # macOS tkinter buttons often ignore the `bg` parameter and remain white. 
        # Using `highlightbackground` helps on Mac, and using black text ensures it's readable regardless.
        self.btn = tk.Button(root, text="🔴 Start Recording", command=self.toggle, bg="darkgrey", fg="black", highlightbackground="darkgrey", height=3, width=20)
        self.btn.pack(pady=20, padx=20)

        # Ensure we close gracefully
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)

    def audio_callback(self, indata, frames, time_info, status):
        # This is called for each audio block from the microphone
        if status:
            print(f"Audio buffer status: {status}")
        self.audio_data.append(indata.copy())

    def toggle(self):
        if not self.is_recording:
            self.is_recording = True
            self.audio_data = []
            
            # Start the sounddevice InputStream directly using CoreAudio (bypasses ffmpeg)
            # It will automatically use whatever microphone is selected in Mac System Settings
            self.stream = sd.InputStream(samplerate=self.samplerate, channels=1, dtype='float32', callback=self.audio_callback)
            self.stream.start()
            
            self.btn.config(text="⏹️ Stop & Save .WAV", bg="black", fg="white", highlightbackground="black")
        else:
            self.is_recording = False
            if self.stream is not None:
                self.stream.stop()
                self.stream.close()
                self.stream = None
            
            self.btn.config(text="🔴 Start Recording", bg="darkgrey", fg="black", highlightbackground="darkgrey")
            
            # Save the file
            project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            filename = os.path.join(project_root, "data", "raw", f"sample_{int(time.time())}.wav")
            os.makedirs(os.path.dirname(filename), exist_ok=True)
            
            if self.audio_data:
                # Concatenate all blocks into a single array
                audio_np = np.concatenate(self.audio_data, axis=0)
                # Soundfile writes cleanly to 16-bit PCM WAV
                sf.write(filename, audio_np, self.samplerate, subtype='PCM_16')
                print(f"Saved recording to: {filename}")
            else:
                print("No audio data was recorded.")

    def on_closing(self):
        if self.stream is not None:
            self.stream.stop()
            self.stream.close()
        self.root.destroy()

if __name__ == "__main__":
    root = tk.Tk()
    app = AudioRecorder(root)
    root.mainloop()