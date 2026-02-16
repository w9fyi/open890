import Interpolate from "./interpolate"
import ColorMap from "./colormap"
import socket from "./socket"
import {WebVoiceProcessor} from "./web-voice-processor"

function PCMPlayer(t){this.init(t)}PCMPlayer.prototype.init=function(t){this.option=Object.assign({},{encoding:"16bitInt",channels:1,sampleRate:8e3,flushingTime:1e3},t),this.samples=new Float32Array,this.flush=this.flush.bind(this),this.interval=setInterval(this.flush,this.option.flushingTime),this.maxValue=this.getMaxValue(),this.typedArray=this.getTypedArray(),this.createContext()},PCMPlayer.prototype.getMaxValue=function(){var t={"8bitInt":128,"16bitInt":32768,"32bitInt":2147483648,"32bitFloat":1};return t[this.option.encoding]?t[this.option.encoding]:t["16bitInt"]},PCMPlayer.prototype.getTypedArray=function(){var t={"8bitInt":Int8Array,"16bitInt":Int16Array,"32bitInt":Int32Array,"32bitFloat":Float32Array};return t[this.option.encoding]?t[this.option.encoding]:t["16bitInt"]},PCMPlayer.prototype.createContext=function(){this.audioCtx=new(window.AudioContext||window.webkitAudioContext),this.gainNode=this.audioCtx.createGain(),this.gainNode.gain.value=1,this.gainNode.connect(this.audioCtx.destination),this.startTime=this.audioCtx.currentTime},PCMPlayer.prototype.isTypedArray=function(t){return t.byteLength&&t.buffer&&t.buffer.constructor==ArrayBuffer},PCMPlayer.prototype.feed=function(t){if(this.isTypedArray(t)){t=this.getFormatedValue(t);var e=new Float32Array(this.samples.length+t.length);e.set(this.samples,0),e.set(t,this.samples.length),this.samples=e}},PCMPlayer.prototype.getFormatedValue=function(t){t=new this.typedArray(t.buffer);var e,i=new Float32Array(t.length);for(e=0;e<t.length;e++)i[e]=t[e]/this.maxValue;return i},PCMPlayer.prototype.volume=function(t){this.gainNode.gain.value=t},PCMPlayer.prototype.destroy=function(){this.interval&&clearInterval(this.interval),this.samples=null,this.audioCtx.close(),this.audioCtx=null},PCMPlayer.prototype.flush=function(){if(this.samples.length){var t,e,i,n,a,s=this.audioCtx.createBufferSource(),r=this.samples.length/this.option.channels,o=this.audioCtx.createBuffer(this.option.channels,r,this.option.sampleRate);for(e=0;e<this.option.channels;e++)for(t=o.getChannelData(e),i=e,a=50,n=0;n<r;n++)t[n]=this.samples[i],n<50&&(t[n]=t[n]*n/50),r-51<=n&&(t[n]=t[n]*a--/50),i+=this.option.channels;this.startTime<this.audioCtx.currentTime&&(this.startTime=this.audioCtx.currentTime),s.buffer=o,s.connect(this.gainNode),s.start(this.startTime),this.startTime+=o.duration,this.samples=new Float32Array}};

let Hooks = {
  AudioRecorder: {
    selectedDeviceId() {
      return window.localStorage.getItem("open890.mic_input_device") || "default"
    },

    applyMicOptions() {
      const selectedDeviceId = this.selectedDeviceId()
      const options = {
        frameLength: 320,
        outputSampleRate: 16000,
      }

      if (selectedDeviceId && selectedDeviceId !== "default") {
        options.deviceId = selectedDeviceId
      }

      WebVoiceProcessor.setOptions(options)
    },

    async startMicCapture() {
      this.applyMicOptions()
      await WebVoiceProcessor.subscribe(this.engine)
      console.log("Success starting VOIP microphone")
    },

    async stopMicCapture() {
      try {
        await WebVoiceProcessor.unsubscribe(this.engine)
      } catch (error) {
        console.error("Failed to stop VOIP microphone", error)
      }
    },

    async handleMicInputSelection(deviceId) {
      const selectedDeviceId = deviceId || this.selectedDeviceId()

      if (!this.micEnabled) {
        window.dispatchEvent(new CustomEvent("open890:mic-input-result", {
          detail: {
            deviceId: selectedDeviceId,
            ok: true,
            reason: "saved"
          }
        }))
        return
      }

      await this.stopMicCapture()
      await this.startMicCapture()

      window.dispatchEvent(new CustomEvent("open890:mic-input-result", {
        detail: {
          deviceId: selectedDeviceId,
          ok: true
        }
      }))
    },

    mounted() {
      let me = this;
      this.micEnabled = false

      this.engine = {
        onmessage: function(e) {
          switch (e.data.command) {
            case 'process':
              const inputData = e.data.inputFrame;
              me.pushEvent("mic_audio", {data: inputData.join(" ")})
              break;
          }
        }
      }

      this.onSetMicInput = async (event) => {
        const requestedDeviceId = event && event.detail && event.detail.deviceId
          ? event.detail.deviceId
          : this.selectedDeviceId()

        try {
          await this.handleMicInputSelection(requestedDeviceId)
        } catch (error) {
          window.dispatchEvent(new CustomEvent("open890:mic-input-result", {
            detail: {
              deviceId: requestedDeviceId,
              ok: false,
              message: error && error.message ? error.message : "Unable to switch microphone"
            }
          }))
          window.alert(error.message)
        }
      }

      window.addEventListener("open890:set-mic-input", this.onSetMicInput)

      this.handleEvent("toggle_mic", (event) => {
        if (event.enabled) {
          this.micEnabled = true

          this.startMicCapture().catch((err) => {
            window.alert(err.message)
          })
        } else {
          this.micEnabled = false
          this.stopMicCapture()
        }
      })
    },

    destroyed() {
      if (this.onSetMicInput) {
        window.removeEventListener("open890:set-mic-input", this.onSetMicInput)
      }

      this.stopMicCapture()
    }

  },
  AudioStream: {
    async setAudioOutputDevice(deviceId) {
      if (!this.player || !this.player.audioCtx) {
        return {ok: false, reason: "player_unavailable"}
      }

      if (typeof this.player.audioCtx.setSinkId !== "function") {
        return {ok: false, reason: "unsupported"}
      }

      try {
        await this.player.audioCtx.setSinkId(deviceId || "default")
        return {ok: true}
      } catch (error) {
        console.error("Unable to set audio output device", error)

        return {
          ok: false,
          reason: "error",
          message: error && error.message ? error.message : "Unable to set audio output device"
        }
      }
    },

    mounted() {
      console.log("AudioStream: mounted")

      this.player = new PCMPlayer({
        encoding: '16bitInt',
        channels: 1,
        sampleRate: 16000,
        flushingTime: 125
      })

      this.audioStreamChannel = socket.channel("radio:audio_stream", {})
      this.audioStreamChannel.join()
        .receive("ok", (resp) => { console.log("joined audio stream channel, resp:", resp) })
        .receive("error", (resp) => {
           console.log("unable to join audio stream channel:", resp)
        })

      this.audioStreamChannel.on("audio_data", (data) => {
        if (this.player) {
          this.player.feed(new Uint8Array(data.payload))
        }
      })

      this.onSetAudioOutput = async (event) => {
        const requestedDeviceId = event && event.detail && event.detail.deviceId ? event.detail.deviceId : "default"
        const result = await this.setAudioOutputDevice(requestedDeviceId)

        window.dispatchEvent(new CustomEvent("open890:audio-output-result", {
          detail: {
            deviceId: requestedDeviceId,
            ...result
          }
        }))
      }

      window.addEventListener("open890:set-audio-output", this.onSetAudioOutput)

      const savedDeviceId = window.localStorage.getItem("open890.audio_output_device") || "default"
      this.onSetAudioOutput({detail: {deviceId: savedDeviceId}})
    },

    destroyed() {
      if (this.audioStreamChannel) {
        this.audioStreamChannel.leave()
      }

      if (this.player) {
        this.player.destroy()
      }

      if (this.onSetAudioOutput) {
        window.removeEventListener("open890:set-audio-output", this.onSetAudioOutput)
      }
    }
  },

  AudioOutputDevice: {
    mounted() {
      this.select = this.el.querySelector("select")
      this.status = this.el.querySelector(".audio-output-status")
      this.storageKey = "open890.audio_output_device"
      this.defaultOptionLabel = "System Default"

      const AudioContextCtor = window.AudioContext || window.webkitAudioContext
      this.isSinkSelectionSupported = !!(
        AudioContextCtor &&
        AudioContextCtor.prototype &&
        typeof AudioContextCtor.prototype.setSinkId === "function"
      )

      this.onOutputResult = (event) => {
        const details = event && event.detail ? event.detail : null

        if (!details || !this.select || details.deviceId !== this.select.value) {
          return
        }

        if (details.ok) {
          const selectedLabel = this.select.options[this.select.selectedIndex]
            ? this.select.options[this.select.selectedIndex].text
            : this.defaultOptionLabel

          this.renderStatus(`Output: ${selectedLabel}`)
          return
        }

        if (details.reason === "unsupported") {
          this.renderStatus("Use your system audio output selector")
          return
        }

        if (details.reason === "player_unavailable") {
          this.renderStatus("Audio player not active")
          return
        }

        this.renderStatus(details.message || "Could not switch output")
      }

      this.onDeviceChange = () => {
        this.populateOutputDevices()
      }

      if (navigator.mediaDevices && typeof navigator.mediaDevices.addEventListener === "function") {
        navigator.mediaDevices.addEventListener("devicechange", this.onDeviceChange)
      }

      window.addEventListener("open890:audio-output-result", this.onOutputResult)

      if (this.select) {
        this.select.addEventListener("change", () => {
          const deviceId = this.select.value || "default"
          window.localStorage.setItem(this.storageKey, deviceId)
          this.dispatchSelection(deviceId)
        })
      }

      this.populateOutputDevices()
    },

    destroyed() {
      if (navigator.mediaDevices && typeof navigator.mediaDevices.removeEventListener === "function" && this.onDeviceChange) {
        navigator.mediaDevices.removeEventListener("devicechange", this.onDeviceChange)
      }

      if (this.onOutputResult) {
        window.removeEventListener("open890:audio-output-result", this.onOutputResult)
      }
    },

    dispatchSelection(deviceId) {
      window.dispatchEvent(new CustomEvent("open890:set-audio-output", {
        detail: {deviceId: deviceId || "default"}
      }))
    },

    setOptions(options, selectedDeviceId) {
      if (!this.select) {
        return
      }

      this.select.innerHTML = ""

      options.forEach((option) => {
        const node = document.createElement("option")
        node.value = option.deviceId
        node.textContent = option.label
        this.select.appendChild(node)
      })

      const hasSelectedDevice = options.some((option) => option.deviceId === selectedDeviceId)
      this.select.value = hasSelectedDevice ? selectedDeviceId : "default"
    },

    async populateOutputDevices() {
      if (!this.select) {
        return
      }

      const savedDeviceId = window.localStorage.getItem(this.storageKey) || "default"

      if (!navigator.mediaDevices || typeof navigator.mediaDevices.enumerateDevices !== "function") {
        this.setOptions([{deviceId: "default", label: this.defaultOptionLabel}], savedDeviceId)
        this.select.disabled = true
        this.renderStatus("Use your system audio output selector")
        return
      }

      try {
        const devices = await navigator.mediaDevices.enumerateDevices()
        const outputDevices = devices.filter((device) => device.kind === "audiooutput")

        const options = [
          {deviceId: "default", label: this.defaultOptionLabel},
          ...outputDevices.map((device, index) => {
            const label = device.label && device.label.trim() !== ""
              ? device.label
              : `Speaker ${index + 1}`

            return {deviceId: device.deviceId, label}
          })
        ]

        this.setOptions(options, savedDeviceId)

        this.select.disabled = !this.isSinkSelectionSupported

        if (!this.isSinkSelectionSupported) {
          this.renderStatus("Use your system audio output selector")
          return
        }

        this.dispatchSelection(this.select.value || "default")
      } catch (error) {
        console.error("Unable to enumerate audio output devices", error)
        this.setOptions([{deviceId: "default", label: this.defaultOptionLabel}], savedDeviceId)
        this.select.disabled = true
        this.renderStatus("Audio outputs unavailable")
      }
    },

    renderStatus(text) {
      if (this.status) {
        this.status.textContent = text
      }
    }
  },

  AudioInputDevice: {
    mounted() {
      this.select = this.el.querySelector("select")
      this.status = this.el.querySelector(".audio-input-status")
      this.storageKey = "open890.mic_input_device"
      this.defaultOptionLabel = "System Default"

      this.onInputResult = (event) => {
        const details = event && event.detail ? event.detail : null

        if (!details || !this.select || details.deviceId !== this.select.value) {
          return
        }

        if (details.ok) {
          const selectedLabel = this.select.options[this.select.selectedIndex]
            ? this.select.options[this.select.selectedIndex].text
            : this.defaultOptionLabel

          this.renderStatus(`Input: ${selectedLabel}`)
          return
        }

        this.renderStatus(details.message || "Could not switch microphone")
      }

      this.onDeviceChange = () => {
        this.populateInputDevices()
      }

      if (navigator.mediaDevices && typeof navigator.mediaDevices.addEventListener === "function") {
        navigator.mediaDevices.addEventListener("devicechange", this.onDeviceChange)
      }

      window.addEventListener("open890:mic-input-result", this.onInputResult)

      if (this.select) {
        this.select.addEventListener("change", () => {
          const deviceId = this.select.value || "default"
          window.localStorage.setItem(this.storageKey, deviceId)
          this.dispatchSelection(deviceId)
        })
      }

      this.populateInputDevices()
    },

    destroyed() {
      if (navigator.mediaDevices && typeof navigator.mediaDevices.removeEventListener === "function" && this.onDeviceChange) {
        navigator.mediaDevices.removeEventListener("devicechange", this.onDeviceChange)
      }

      if (this.onInputResult) {
        window.removeEventListener("open890:mic-input-result", this.onInputResult)
      }
    },

    dispatchSelection(deviceId) {
      window.dispatchEvent(new CustomEvent("open890:set-mic-input", {
        detail: {deviceId: deviceId || "default"}
      }))
    },

    setOptions(options, selectedDeviceId) {
      if (!this.select) {
        return
      }

      this.select.innerHTML = ""

      options.forEach((option) => {
        const node = document.createElement("option")
        node.value = option.deviceId
        node.textContent = option.label
        this.select.appendChild(node)
      })

      const hasSelectedDevice = options.some((option) => option.deviceId === selectedDeviceId)
      this.select.value = hasSelectedDevice ? selectedDeviceId : "default"
    },

    async populateInputDevices() {
      if (!this.select) {
        return
      }

      const savedDeviceId = window.localStorage.getItem(this.storageKey) || "default"

      if (!navigator.mediaDevices || typeof navigator.mediaDevices.enumerateDevices !== "function") {
        this.setOptions([{deviceId: "default", label: this.defaultOptionLabel}], savedDeviceId)
        this.select.disabled = true
        this.renderStatus("Microphone devices unavailable")
        return
      }

      try {
        const devices = await navigator.mediaDevices.enumerateDevices()
        const inputDevices = devices.filter((device) => device.kind === "audioinput")

        const options = [
          {deviceId: "default", label: this.defaultOptionLabel},
          ...inputDevices.map((device, index) => {
            const label = device.label && device.label.trim() !== ""
              ? device.label
              : `Microphone ${index + 1}`

            return {deviceId: device.deviceId, label}
          })
        ]

        this.setOptions(options, savedDeviceId)
        this.select.disabled = false
        this.dispatchSelection(this.select.value || "default")
      } catch (error) {
        console.error("Unable to enumerate microphone devices", error)
        this.setOptions([{deviceId: "default", label: this.defaultOptionLabel}], savedDeviceId)
        this.select.disabled = true
        this.renderStatus("Microphone devices unavailable")
      }
    },

    renderStatus(text) {
      if (this.status) {
        this.status.textContent = text
      }
    }
  },
  Tabs: {
    mounted() {
      $('#ButtonTabs .item').tab();
    }

  },
  PopoutBandscope: {
    mounted() {
      console.log("popoutbandscope mounted")
      let me = this;
      this.el.addEventListener("click", event => {
        event.preventDefault()

        let id = this.el.dataset.connectionId
        let url = `/connections/${id}/bandscope?popout`
        me.window = window.open(url, `bandscope-${id}`, "width=1500,height=780,popup=true,menubar=off,scrollbars=off")
      })
    }
  },

  MaintainAttrs: {
    attrs(){ return this.el.getAttribute("data-attrs").split(", ") },
    beforeUpdate(){ this.prevAttrs = this.attrs().map(name => [name, this.el.getAttribute(name)]) },
    updated(){ this.prevAttrs.forEach(([name, val]) => this.el.setAttribute(name, val)) }
  },

  DirectFrequencyEntryForm: {
    mounted() {
      this.freqInput = this.el.querySelector("#direct-frequency-entry-field")
      this.entButton = this.el.querySelector("#direct-frequency-entry-submit")
      this.freq = this.freqInput.value;

      let me = this

      if (this.freqInput) {
        this.freqInput.addEventListener("click", event => {
          me.freqInput.select()
        })

        this.freqInput.addEventListener("blur", event => {
          this.freq = this.freqInput.value;
        })
      }

      if (this.entButton) {
        this.entButton.addEventListener("click", event => {
          // me.freqInput.blur()
          me.pushEvent("direct_frequency_entry", {freq: this.freq})
        })
      }

      this.el.addEventListener("submit", event => {
        event.preventDefault()

        if (this.freqInput) {
          // this allows the field to update - otherwise phoenix won't change a field with focus
          this.freqInput.blur()
          this.pushEvent("direct_frequency_entry", {freq: this.freq})
        }
      })


      this.freqInput.select()
    }

  },
  ActiveVFO: {
    mounted() {
      console.log("ActiveVFO mounted")
      this.el.addEventListener("click", event => {
        this.pushEvent("toggle_band_selector")
      })

      // this.el.addEventListener("wheel", event => {
      //   event.preventDefault()
      // })
    }

  },

  RefLevelControl: {
    mounted() {
      console.log("ref level mount")
      this.el.addEventListener("wheel", event => {
        event.preventDefault();
        console.log("ref level wheel", event)

        var isScrollUp = (event.deltaY < 0)
        this.pushEvent("adjust_ref_level", {is_up: isScrollUp})
      })
    }
  },

  RitXitControl: {
    copyTouch({identifier, pageX, pageY}) {
      return { identifier, pageX, pageY }
    },

    mounted() {
      this.el.addEventListener("wheel", (event) => {
        event.preventDefault();

        var isScrollUp = event.deltaY < 0;
        this.pushEvent("adjust_rit_xit", {is_up: isScrollUp})
      })

      this.el.addEventListener("keydown", (event) => {
        switch (event.key) {
          case "ArrowUp":
          case "ArrowRight":
          case "PageUp":
            event.preventDefault()
            this.pushEvent("adjust_rit_xit", {is_up: true})
            break
          case "ArrowDown":
          case "ArrowLeft":
          case "PageDown":
            event.preventDefault()
            this.pushEvent("adjust_rit_xit", {is_up: false})
            break
        }
      })

      this.el.addEventListener("touchstart", (event) => {
        var me = this;

        if (event.changedTouches[0]) {
          let touch = event.changedTouches[0];
          me.prevTouch = this.copyTouch(touch);
        }
      })

      this.el.addEventListener("touchend", (event) => {
        var me = this;
        event.preventDefault();
        me.prevTouch = null;
      })

      this.el.addEventListener("touchmove", (event) => {
        event.preventDefault();
        var me = this;

        if (event.changedTouches[0]) {
          if (me.prevTouch) {
            let touch = event.changedTouches[0];

            let deltaX = touch.pageX - me.prevTouch.pageX;
            let deltaY = touch.pageY - me.prevTouch.pageY;

            let isUp = deltaX > 0;
            console.log("move dx/dy:", deltaX, deltaY);

            if (Math.abs(deltaX) > 5) {
              this.pushEvent("adjust_rit_xit", {is_up: isUp})
            }
          }
        }
      })

      //this.el.addEventListener("mousedown", (event) => {
      //  event.preventDefault();
      //  me.dragStartCoord = event.x;

      //  console.log("RIT/XIT mouseDown", event.x)
      //})


      //this.el.addEventListener("mouseup", (event) => {
      //  event.preventDefault();


      //  console.log("RIT/XIT mouseUp", event.x)
      //})

      //this.el.addEventListener("mousemove", event => {
      //  event.preventDefault();

      //  if (event.buttons && event.buttons == 1) {
      //    console.log("rit/xit drag", event)
      //  }
      //})
    },


  },

  MultiCH: {
    mounted() {
      this.el.addEventListener("wheel", event => {
        event.preventDefault();

        var isScrollUp = (event.deltaY < 0)
        this.pushEvent("multi_ch", {is_up: isScrollUp})
      })
    }
  },

  Marker: {
    mounted() {
      console.log("marker mounted")
      let me = this;

      this.el.addEventListener("mouseover", event => {
        console.log("marker hover:", event)
      })
    }

  },

  BandScope: {
    tuneToClick(event) {
      event.preventDefault()

      let svg = document.querySelector('svg#bandScope');
      let pt = svg.createSVGPoint();

      pt.x = event.clientX;
      pt.y = event.clientY;

      var cursorPt = pt.matrixTransform(svg.getScreenCTM().inverse());
      this.pushEvent("scope_clicked", {x: cursorPt.x, y: cursorPt.y, width: 640})
    },

    mounted() {
      let me = this;

      let scaleKey = 'bandscope.spectrum_scale'
      this.spectrumScale = localStorage.getItem(scaleKey) || 140
      this.locked = false;

      this.handleEvent("lock_state", (event) => {
        me.locked = event.locked;
      })

      this.el.addEventListener("wheel", event => {
        // This is duplicated in the BandScopeCanvas hook below
        event.preventDefault();

        if (me.locked) { return; }

        var isScrollUp = (event.deltaY < 0);
        var stepSize = 0;

        if (event.shiftKey) {
          stepSize = 5
        }

        if (isScrollUp) {
          if (event.shiftKey) {
            this.pushEvent("multi_ch", {is_up: true})
          } else {
            this.pushEvent("step_tune_up", {stepSize: stepSize})

          }
        } else {
          if (event.shiftKey) {
            this.pushEvent("multi_ch", {is_up: false})
          } else {
            this.pushEvent("step_tune_down", {stepSize: stepSize})
          }
        }

      });

      this.el.addEventListener("mousemove", event => {
        if (me.locked) { return; }

        if (event.buttons && event.buttons == 1) {
          this.tuneToClick(event)
        }
      })

      this.el.addEventListener("mousedown", (event) => {
        if (me.locked) { return; }
        this.tuneToClick(event)
      })
    }
  },
  AudioScope: {
    mounted() {
      this.el.addEventListener("wheel", (event) => {
        event.preventDefault();
        const isScrollUp = event.deltaY < 0;

        const dir = isScrollUp ? "up" : "down";
        const isShifted = event.shiftKey;

        console.log("audioScope wheel, dir:", dir, "shifted", isShifted, "event:", event);
        this.pushEvent("adjust_filter", {dir: dir, shift: isShifted})
      });

      this.el.addEventListener("click", (event) => {
        event.preventDefault();
        this.pushEvent("cw_tune", {})
      })

      this.el.addEventListener("keydown", (event) => {
        switch (event.key) {
          case "ArrowUp":
          case "ArrowRight":
            event.preventDefault()
            this.pushEvent("adjust_filter", {dir: "up", shift: event.shiftKey})
            break
          case "ArrowDown":
          case "ArrowLeft":
            event.preventDefault()
            this.pushEvent("adjust_filter", {dir: "down", shift: event.shiftKey})
            break
          case "Enter":
          case " ":
            event.preventDefault()
            this.pushEvent("cw_tune", {})
            break
        }
      })
    }
  },
  AudioScopeCanvas: {
    updated() {
      this.theme = this.el.dataset.theme;
    },

    clearScope() {
      if (this.ctx) {
        this.ctx.save();
        this.ctx.fillStyle = 'black';
        this.ctx.fillRect(0, 0, this.width, this.height)
        this.ctx.restore()
      }
    },

    mounted() {
      console.log("audioscope canvas mounted")

      this.canvas = this.el
      this.ctx = this.canvas.getContext("2d")

      this.multiplier = 0.6
      this.theme = this.el.dataset.theme;
      this.draw = true

      // these items should be computed or passed in via data- attributes
      this.maxVal = 50
      this.width = 212
      this.height = 50

      this.clearScope()

      this.el.addEventListener("click", (event) => {
        event.preventDefault();
        this.pushEvent("cw_tune", {})
      })

      this.handleEvent("scope_data", (event) => {
        if (this.draw) {
          let data = event.scope_data;

          this.ctx.drawImage(this.canvas, 0, 1)

          let imgData = this.ctx.createImageData(data.length, 1)
          let i = 0;

          for(i; i < data.length; i++) {
            let val = Interpolate.linear(data[i], 0, this.maxVal, 255, 0) * this.multiplier

            const mappedColor = ColorMap.applyMap(val, this.theme)

            imgData.data[4*i + 0] = mappedColor[0]
            imgData.data[4*i + 1] = mappedColor[1]
            imgData.data[4*i + 2] = mappedColor[2]
            imgData.data[4*i + 3] = mappedColor[3]

          }
          this.ctx.putImageData(imgData, 0, 0)
        }
      });
    }
  },
  BandScopeCanvas: {
    updated() {
      this.theme = this.el.dataset.theme
      this.drawInterval = this.el.dataset.drawInterval;
    },

    tuneToClick(event) {
      let rect = this.canvas.getBoundingClientRect()

      let scaleX = this.canvas.width / rect.width;
      let scaleY = this.canvas.height / rect.height;

      let x = (event.clientX - rect.left) * scaleX;
      let y = (event.clientY - rect.top) * scaleY;

      this.pushEvent("scope_clicked", {x: x, y: y, width: 1280})
    },

    clearScope() {
      if (this.ctx) {
        this.ctx.save();
        this.ctx.fillStyle = 'black';
        this.ctx.fillRect(0, 0, this.width, this.height)
        this.ctx.restore()
      }
    },

    resumeDrawing(ctx) {
      ctx.packetCount = 0;
      ctx.draw = true;
    },

    mounted() {
      let me = this;

      this.resumeDrawtimer = null;
      console.log("bandscope canvas mounted")
      this.canvas = this.el
      this.ctx = this.canvas.getContext("2d")
      this.drawInterval = this.el.dataset.drawInterval;
      this.locked = false;

      this.maxVal = this.el.dataset.maxValue;
      this.width = this.el.getAttribute('width')
      this.height = this.el.getAttribute('height')

      this.ctx.imageSmoothingEnabled = false;
      this.ctx.imageSmoothingQuality = 'high';
      // this.ctx.globalCompositeOperation = 'color'
      console.log("smoothing", this.ctx.imageSmoothingEnabled);

      this.multiplier = 1.3
      this.theme = this.el.dataset.theme
      this.draw = true
      this.packetCount = 0;

      this.clearScope()

      this.handleEvent("lock_state", (event) => {
        me.locked = event.locked;
      })

      this.handleEvent("clear_band_scope", (event) => {
        this.clearScope()
      })

      this.el.addEventListener("wheel", event => {
        // this is duplicated in the BandScope hooks above

        event.preventDefault();
        if (me.locked) { return; }

        var isScrollUp = (event.deltaY < 0);
        var stepSize = 0;

        if (event.shiftKey) {
          stepSize = 5
        }

        if (isScrollUp) {
          if (event.shiftKey) {
            this.pushEvent("multi_ch", {is_up: true})
          } else {
            this.pushEvent("step_tune_up", {stepSize: stepSize})

          }
        } else {
          if (event.shiftKey) {
            this.pushEvent("multi_ch", {is_up: false})
          } else {
            this.pushEvent("step_tune_down", {stepSize: stepSize})
          }
        }
      });

      this.el.addEventListener("keydown", event => {
        if (me.locked) { return; }

        switch (event.key) {
          case "ArrowUp":
          case "ArrowRight":
          case "PageUp":
            event.preventDefault()
            if (event.shiftKey) {
              this.pushEvent("multi_ch", {is_up: true})
            } else {
              this.pushEvent("step_tune_up", {stepSize: 0})
            }
            break
          case "ArrowDown":
          case "ArrowLeft":
          case "PageDown":
            event.preventDefault()
            if (event.shiftKey) {
              this.pushEvent("multi_ch", {is_up: false})
            } else {
              this.pushEvent("step_tune_down", {stepSize: 0})
            }
            break
        }
      })

      this.el.addEventListener("mousemove", event => {
        if (me.locked) { return; }

        if (event.buttons && event.buttons == 1) {
          this.tuneToClick(event)
        }
      })

      this.el.addEventListener("mousedown", event => {
        if (me.locked) { return; }
        this.tuneToClick(event);
      })

      this.handleEvent("freq_delta", (event) => {
        // console.log("freq_delta", event)
        // interpolate delta event.bs.low ... event.bs.high to the scope size
        this.draw = false

        if (this.resumeDrawTimer) {
          clearTimeout(this.resumeDrawTimer)
        }

        this.resumeDrawTimer = setTimeout(this.resumeDrawing, 200, this);

        let rect = this.canvas.getBoundingClientRect()
        let scaleX = this.canvas.width / rect.width

        let bs_delta = event.bs.high - event.bs.low

        let widthScale = bs_delta / this.canvas.width

        let canvasDelta = event.delta / widthScale
        let width = Math.abs(canvasDelta)

        //console.log("canvasDelta:", canvasDelta)

        this.ctx.drawImage(this.canvas, -canvasDelta, 0)

        if (canvasDelta < 0) {
          // left side
          this.ctx.fillStyle = '#000'
          this.ctx.fillRect(0, 0, width, this.canvas.height)
        } else if (canvasDelta > 0) {
          // right side
          this.ctx.fillStyle = '#000'
          this.ctx.fillRect(this.canvas.width - width, 0, width, this.height)
        }
      }).bind(this)

      this.handleEvent("band_scope_data", (event) => {
        this.packetCount += 1;

        if (this.draw && (this.packetCount % this.drawInterval) == 0) {
          this.packetCount = 0;
          let data = event.scope_data

          this.ctx.drawImage(this.canvas, 0, 1)

          let imgData = this.ctx.createImageData(data.length * 2, 1)

          let i = 0;

          for(i; i < data.length; i++) {

            // interpolate signal strength to 0..255
            let val = Interpolate.linear(data[i], 0, 140, 255, 0) * this.multiplier

            const mappedColor = ColorMap.applyMap(val, this.theme)

            imgData.data[8*i + 0] = mappedColor[0]
            imgData.data[8*i + 1] = mappedColor[1]
            imgData.data[8*i + 2] = mappedColor[2]
            imgData.data[8*i + 3] = mappedColor[3]

            imgData.data[8*i + 4] = mappedColor[0]
            imgData.data[8*i + 5] = mappedColor[1]
            imgData.data[8*i + 6] = mappedColor[2]
            imgData.data[8*i + 7] = mappedColor[3]


            // imgData.data[4*(i*2) + 0 + ] = mappedColor[0]
            // imgData.data[4*(i*2) + 1 + ] = mappedColor[1]
            // imgData.data[4*(i*2) + 2 + ] = mappedColor[2]
            // imgData.data[4*(i*2) + 3 + ] = mappedColor[3]

          }

          this.ctx.putImageData(imgData, 0, 0)
        }
      });
    }
  },

  Slider: {
    mounted() {
      this.action = this.el.dataset.clickAction
      this.wheelAction = this.el.dataset.wheelAction
      this.rangeInput = this.el.querySelector(".sliderRangeInput")

      this.applyValue(this.currentValue())

      if (this.rangeInput) {
        this.rangeInput.addEventListener("input", (event) => {
          if (!this.isEnabled()) {
            return
          }

          const nextValue = this.applyValue(Number(event.target.value))
          this.pushAbsolute(nextValue)
        })
      }

      this.el.addEventListener("wheel", (event) => {
        event.preventDefault()

        if (!this.isEnabled()) {
          return
        }

        const isScrollUp = event.deltaY < 0
        this.nudge(isScrollUp)
      })
    },

    updated() {
      this.applyValue(this.currentValue())
    },

    isEnabled() {
      return this.el.dataset.enabled === "true"
    },

    maxValue() {
      const parsed = Number(this.el.dataset.maxValue)

      if (Number.isFinite(parsed)) {
        return parsed
      }

      return 255
    },

    stepValue() {
      if (this.rangeInput) {
        const inputStep = Number(this.rangeInput.step)

        if (Number.isFinite(inputStep) && inputStep > 0) {
          return inputStep
        }
      }

      const parsed = Number(this.el.dataset.step)

      if (Number.isFinite(parsed) && parsed > 0) {
        return parsed
      }

      return 1
    },

    currentValue() {
      if (this.rangeInput) {
        const inputValue = Number(this.rangeInput.value)

        if (Number.isFinite(inputValue)) {
          return inputValue
        }
      }

      const parsed = Number(this.el.dataset.currentValue)

      if (Number.isFinite(parsed)) {
        return parsed
      }

      return 0
    },

    clamp(value) {
      return Math.max(0, Math.min(this.maxValue(), value))
    },

    applyValue(value) {
      const clamped = this.clamp(Math.round(value))

      this.el.dataset.currentValue = String(clamped)

      if (this.rangeInput) {
        this.rangeInput.value = String(clamped)

        const label = this.rangeInput.getAttribute("aria-label") || "slider"
        this.rangeInput.setAttribute("aria-valuenow", String(clamped))
        this.rangeInput.setAttribute("aria-valuetext", `${label}: ${clamped}`)
      }

      const indicator = this.el.querySelector(".indicator")
      if (indicator) {
        const max = this.maxValue()
        const width = max > 0 ? Math.round((clamped / max) * 255) : 0
        indicator.style.width = `${width}px`
      }

      return clamped
    },

    pushAbsolute(value) {
      if (this.action) {
        this.pushEvent(this.action, {value: value})
      }
    },

    nudge(isUp) {
      const delta = isUp ? this.stepValue() : -this.stepValue()
      const nextValue = this.applyValue(this.currentValue() + delta)

      if (this.action) {
        this.pushEvent(this.action, {value: nextValue})
      } else if (this.wheelAction) {
        this.pushEvent(this.wheelAction, {is_up: isUp})
      }
    }
  },

  SpectrumScaleForm: {
    mounted() {
      const key = 'bandscope.spectrum_scale'
      let val = localStorage.getItem(key)

      if (!val) {
        localStorage.setItem(key, 1.0)
      } else {
        this.pushEvent('spectrum_scale_changed', {value: val})
      }

      this.el.addEventListener('change', (event) => {
        const val = event.target.value;
        console.log("scale changed", val)

        localStorage.setItem(key, val)
        this.pushEvent('spectrum_scale_changed', {value: val})
      })
    }
  },

  WaterfallSpeedForm: {
    mounted() {
      console.log("WF speed form mounted")

      const key = 'bandscope.waterfall_speed'
      let wfSpeed = localStorage.getItem(key)

      if (!wfSpeed) {
        localStorage.setItem(key, '1')
      } else {
        this.pushEvent('wf_speed_changed', {value: wfSpeed})
      }

      this.el.addEventListener('change', (event) => {
        const val = event.target.value;

        localStorage.setItem(key, val)
        this.pushEvent('wf_speed_changed', {value: val})
      })
    }
  },
  RadioKeyboard: {
    mounted() {
      //this.el.addEventListener("keyup", event => {
      //  console.log("keyUp:", event)
      //})
    }
  },

}
export default Hooks
