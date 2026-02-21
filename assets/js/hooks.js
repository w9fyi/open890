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

    async requestMicrophonePermission() {
      if (!navigator.mediaDevices || typeof navigator.mediaDevices.getUserMedia !== "function") {
        return {
          ok: false,
          message: "Microphone permissions are unavailable in this browser"
        }
      }

      try {
        const stream = await navigator.mediaDevices.getUserMedia({audio: true})
        stream.getTracks().forEach((track) => track.stop())
        return {ok: true}
      } catch (error) {
        if (error && error.name === "NotAllowedError") {
          return {ok: false, message: "Microphone permission denied"}
        }

        if (error && error.name === "NotFoundError") {
          return {ok: false, message: "No microphone available"}
        }

        if (error && error.name === "NotReadableError") {
          return {ok: false, message: "Microphone is busy or unavailable"}
        }

        if (error && error.name === "SecurityError") {
          return {ok: false, message: "Microphone access requires a secure browser context"}
        }

        return {
          ok: false,
          message: error && error.message ? error.message : "Unable to request microphone permission"
        }
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

      this.onMicButtonClick = (event) => {
        const button = event.target.closest('button[phx-click="toggle_mic"]')

        if (!button) {
          return
        }

        event.preventDefault()
        event.stopImmediatePropagation()

        const currentlyEnabled = button.getAttribute("aria-pressed") === "true"

        if (currentlyEnabled) {
          this.pushEvent("toggle_mic", {})
          return
        }

        this.requestMicrophonePermission().then((permission) => {
          if (!permission.ok) {
            window.alert(permission.message)
            return
          }

          this.pushEvent("toggle_mic", {})
        })
      }

      this.el.addEventListener("click", this.onMicButtonClick, true)
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

      if (this.onMicButtonClick) {
        this.el.removeEventListener("click", this.onMicButtonClick, true)
      }

      this.stopMicCapture()
    }

  },
  AudioStream: {
    async setAudioOutputDevice(deviceId) {
      if (!this.player || !this.player.audioCtx) {
        return {ok: false, reason: "player_unavailable"}
      }

      const mediaElementDeviceId = !deviceId || deviceId === "default" ? "" : deviceId
      const audioContextDeviceId = !deviceId || deviceId === "default" ? "default" : deviceId
      let lastError = null

      try {
        if (this.outputElement && typeof this.outputElement.setSinkId === "function") {
          try {
            await this.outputElement.setSinkId(mediaElementDeviceId)
          } catch (error) {
            lastError = error
          }

          if (!lastError) {
            if (this.outputElement.paused) {
              await this.outputElement.play()
            }

            return {ok: true}
          }
        }

        if (typeof this.player.audioCtx.setSinkId === "function") {
          await this.player.audioCtx.setSinkId(audioContextDeviceId)
          return {ok: true}
        }

        if (lastError) {
          throw lastError
        }

        return {ok: false, reason: "unsupported"}
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

      this.outputElement = null

      const mediaElementSupportsSink = !!(
        typeof HTMLMediaElement !== "undefined" &&
        HTMLMediaElement.prototype &&
        typeof HTMLMediaElement.prototype.setSinkId === "function"
      )

      if (mediaElementSupportsSink) {
        try {
          const streamDestination = this.player.audioCtx.createMediaStreamDestination()
          this.player.gainNode.disconnect()
          this.player.gainNode.connect(streamDestination)

          this.outputElement = document.createElement("audio")
          this.outputElement.autoplay = true
          this.outputElement.playsInline = true
          this.outputElement.srcObject = streamDestination.stream
          this.outputElement.style.display = "none"
          this.el.appendChild(this.outputElement)
        } catch (error) {
          console.error("Unable to initialize audio output element", error)
          this.outputElement = null
        }
      }

      this.resumeAudioContext = async () => {
        if (!this.player || !this.player.audioCtx) {
          return
        }

        if (this.player.audioCtx.state === "suspended") {
          try {
            await this.player.audioCtx.resume()
          } catch (error) {
            console.debug("Audio context resume deferred", error)
          }
        }

        if (this.outputElement && this.outputElement.paused) {
          try {
            await this.outputElement.play()
          } catch (error) {
            console.debug("Audio output element play deferred", error)
          }
        }
      }

      this.onUnlockAudio = () => {
        this.resumeAudioContext()
      }

      this.bindAudioUnlockHandlers = () => {
        document.addEventListener("click", this.onUnlockAudio, {passive: true})
        document.addEventListener("touchstart", this.onUnlockAudio, {passive: true})
        document.addEventListener("keydown", this.onUnlockAudio)
      }

      this.unbindAudioUnlockHandlers = () => {
        document.removeEventListener("click", this.onUnlockAudio)
        document.removeEventListener("touchstart", this.onUnlockAudio)
        document.removeEventListener("keydown", this.onUnlockAudio)
      }

      this.bindAudioUnlockHandlers()

      this.audioStreamChannel = socket.channel("radio:audio_stream", {})
      this.audioStreamChannel.join()
        .receive("ok", async (resp) => {
          console.log("joined audio stream channel, resp:", resp)
          await this.resumeAudioContext()
        })
        .receive("error", (resp) => {
           console.log("unable to join audio stream channel:", resp)
        })

      this.audioStreamChannel.on("audio_data", (data) => {
        this.resumeAudioContext()

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

      if (this.outputElement) {
        this.outputElement.pause()
        this.outputElement.srcObject = null
        this.outputElement.remove()
      }

      if (this.player) {
        this.player.destroy()
      }

      if (this.unbindAudioUnlockHandlers) {
        this.unbindAudioUnlockHandlers()
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
      this.storageLabelKey = "open890.audio_output_device_label"
      this.defaultOptionLabel = "System Default"
      this.pickOutputOptionValue = "__pick_output_device__"
      this.canPromptForOutput = !!(
        navigator.mediaDevices &&
        typeof navigator.mediaDevices.selectAudioOutput === "function"
      )

      const AudioContextCtor = window.AudioContext || window.webkitAudioContext
      const audioContextSinkSupported = !!(
        AudioContextCtor &&
        AudioContextCtor.prototype &&
        typeof AudioContextCtor.prototype.setSinkId === "function"
      )
      const mediaElementSinkSupported = !!(
        typeof HTMLMediaElement !== "undefined" &&
        HTMLMediaElement.prototype &&
        typeof HTMLMediaElement.prototype.setSinkId === "function"
      )

      this.isSinkSelectionSupported = audioContextSinkSupported || mediaElementSinkSupported

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
          const isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent)
          this.renderStatus(isSafari
            ? "Safari does not support audio output selection. Use Chrome or Firefox for per-device routing."
            : "Your browser does not support audio output selection.")
          return
        }

        if (details.reason === "player_unavailable") {
          this.renderStatus("Audio player not active")
          return
        }

        this.renderStatus(details.message || "Could not switch output")
      }

      this.onDeviceChange = () => {
        this.populateOutputDevices(window.localStorage.getItem(this.storageKey) || "default")
      }

      if (navigator.mediaDevices && typeof navigator.mediaDevices.addEventListener === "function") {
        navigator.mediaDevices.addEventListener("devicechange", this.onDeviceChange)
      }

      window.addEventListener("open890:audio-output-result", this.onOutputResult)

      if (this.select) {
        this.select.addEventListener("change", async () => {
          const previousDeviceId = window.localStorage.getItem(this.storageKey) || "default"
          let deviceId = this.select.value || "default"
          const selectedLabel = this.select.options[this.select.selectedIndex]
            ? this.select.options[this.select.selectedIndex].text
            : this.defaultOptionLabel

          if (deviceId === this.pickOutputOptionValue) {
            const selected = await this.promptForOutputSelection()
            await this.populateOutputDevices(selected ? selected.deviceId : previousDeviceId)
            return
          }

          if (deviceId !== "default" && this.canPromptForOutput) {
            const selected = await this.promptForOutputSelection(deviceId)

            if (!selected) {
              await this.populateOutputDevices(previousDeviceId)
              return
            }

            deviceId = selected.deviceId || deviceId
            this.persistSelection(deviceId, selected.label || selectedLabel)
            await this.populateOutputDevices(deviceId)
            return
          }

          this.persistSelection(deviceId, selectedLabel)
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

    async promptForOutputSelection(preferredDeviceId = null) {
      if (!this.canPromptForOutput) {
        return null
      }

      try {
        if (preferredDeviceId && preferredDeviceId !== "default") {
          return await navigator.mediaDevices.selectAudioOutput({deviceId: preferredDeviceId})
        }

        return await navigator.mediaDevices.selectAudioOutput()
      } catch (error) {
        if (error && error.name === "NotAllowedError") {
          this.renderStatus("Speaker selection permission was denied")
          return null
        }

        if (error && error.name === "NotFoundError") {
          this.renderStatus("No alternate audio output devices were found")
          return null
        }

        if (error && error.name === "NotSupportedError") {
          this.renderStatus("Browser does not support speaker selection prompt")
          return null
        }

        console.error("Unable to prompt for audio output selection", error)
        this.renderStatus("Unable to open speaker selector")
        return null
      }
    },

    dispatchSelection(deviceId) {
      window.dispatchEvent(new CustomEvent("open890:set-audio-output", {
        detail: {deviceId: deviceId || "default"}
      }))
    },

    persistSelection(deviceId, label) {
      const resolvedDeviceId = deviceId || "default"
      window.localStorage.setItem(this.storageKey, resolvedDeviceId)

      if (resolvedDeviceId === "default") {
        window.localStorage.removeItem(this.storageLabelKey)
        return
      }

      if (label && label.trim() !== "") {
        window.localStorage.setItem(this.storageLabelKey, label)
      }
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

    async populateOutputDevices(preferredDeviceId) {
      if (!this.select) {
        return
      }

      const savedDeviceId = preferredDeviceId || window.localStorage.getItem(this.storageKey) || "default"
      const savedDeviceLabel = window.localStorage.getItem(this.storageLabelKey) || ""

      if (!window.isSecureContext) {
        this.setOptions([{deviceId: "default", label: this.defaultOptionLabel}], savedDeviceId)
        this.select.disabled = true
        this.renderStatus("Use HTTPS to select browser audio outputs")
        return
      }

      if (!navigator.mediaDevices || typeof navigator.mediaDevices.enumerateDevices !== "function") {
        this.setOptions([{deviceId: "default", label: this.defaultOptionLabel}], savedDeviceId)
        this.select.disabled = true
        this.renderStatus("Use your system audio output selector")
        return
      }

      try {
        const devices = await navigator.mediaDevices.enumerateDevices()
        const outputDevices = devices.filter((device) => device.kind === "audiooutput" && device.deviceId !== "default")

        const options = [
          {deviceId: "default", label: this.defaultOptionLabel},
          ...outputDevices.map((device, index) => {
            const label = device.label && device.label.trim() !== ""
              ? device.label
              : `Speaker ${index + 1}`

            return {deviceId: device.deviceId, label}
          })
        ]

        if (this.canPromptForOutput) {
          options.push({deviceId: this.pickOutputOptionValue, label: "Select output device..."})
        }

        let resolvedDeviceId = savedDeviceId
        let missingSavedDevice = false

        if (resolvedDeviceId !== "default" && !options.some((option) => option.deviceId === resolvedDeviceId)) {
          const labelMatch = savedDeviceLabel && savedDeviceLabel.trim() !== ""
            ? options.find((option) => option.deviceId !== "default" && option.label === savedDeviceLabel)
            : null

          if (labelMatch) {
            resolvedDeviceId = labelMatch.deviceId
            this.persistSelection(labelMatch.deviceId, labelMatch.label)
          } else {
            const fallbackLabel = savedDeviceLabel && savedDeviceLabel.trim() !== ""
              ? `${savedDeviceLabel} (reselect)`
              : "Saved output (reselect)"
            options.splice(1, 0, {deviceId: savedDeviceId, label: fallbackLabel})
            missingSavedDevice = true
          }
        }

        this.setOptions(options, resolvedDeviceId)

        this.select.disabled = !this.isSinkSelectionSupported

        if (!this.isSinkSelectionSupported) {
          const isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent)
          this.renderStatus(isSafari
            ? "Safari does not support output selection. Use Chrome or Firefox."
            : "Your browser does not support audio output selection.")
          return
        }

        if (options.length <= 2 && this.canPromptForOutput) {
          this.renderStatus("Only default output is visible. Use 'Select output device...' to grant speaker access.")
        }

        if (missingSavedDevice) {
          this.renderStatus("Saved output device needs permission. Use 'Select output device...' to re-authorize it.")
          return
        }

        const selectedDeviceId = this.select.value || "default"

        if (selectedDeviceId === this.pickOutputOptionValue) {
          return
        }

        const selectedLabel = this.select.options[this.select.selectedIndex]
          ? this.select.options[this.select.selectedIndex].text
          : this.defaultOptionLabel
        this.persistSelection(selectedDeviceId, selectedLabel)
        this.dispatchSelection(selectedDeviceId)
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
      this.storageLabelKey = "open890.mic_input_device_label"
      this.defaultOptionLabel = "System Default"
      this.pickInputOptionValue = "__pick_input_device__"
      this.pickInputOptionLabel = "Enable microphone list..."
      this.canPromptForMicInput =
        navigator.mediaDevices &&
        typeof navigator.mediaDevices.getUserMedia === "function"
      this.hasRequestedMicPermission = false

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
        this.populateInputDevices(window.localStorage.getItem(this.storageKey) || "default")
      }

      if (navigator.mediaDevices && typeof navigator.mediaDevices.addEventListener === "function") {
        navigator.mediaDevices.addEventListener("devicechange", this.onDeviceChange)
      }

      window.addEventListener("open890:mic-input-result", this.onInputResult)

      this.onSelectFocus = async () => {
        if (!this.select || this.hasRequestedMicPermission) {
          return
        }

        this.hasRequestedMicPermission = true
        const permission = await this.requestMicrophonePermission()

        if (!permission.ok) {
          this.hasRequestedMicPermission = false
          this.renderStatus(permission.message)
          return
        }

        await this.populateInputDevices(window.localStorage.getItem(this.storageKey) || "default")
      }

      if (this.select) {
        this.select.addEventListener("focus", this.onSelectFocus)
        this.select.addEventListener("change", async () => {
          const requestedDeviceId = this.select.value || "default"
          const previousDeviceId = window.localStorage.getItem(this.storageKey) || "default"
          const selectedLabel = this.select.options[this.select.selectedIndex]
            ? this.select.options[this.select.selectedIndex].text
            : this.defaultOptionLabel

          if (requestedDeviceId === this.pickInputOptionValue) {
            this.hasRequestedMicPermission = true
            this.renderStatus("Waiting for microphone permission...")
            const permission = await this.requestMicrophonePermission()

            if (!permission.ok) {
              this.hasRequestedMicPermission = false
              this.renderStatus(permission.message)
            }

            await this.populateInputDevices(previousDeviceId)
            return
          }

          if (requestedDeviceId !== "default") {
            this.hasRequestedMicPermission = true
            const permission = await this.requestMicrophonePermission()

            if (!permission.ok) {
              this.hasRequestedMicPermission = false
              window.dispatchEvent(new CustomEvent("open890:mic-input-result", {
                detail: {
                  deviceId: requestedDeviceId,
                  ok: false,
                  message: permission.message
                }
              }))
              await this.populateInputDevices(previousDeviceId)
              return
            }

            this.renderStatus("Switching microphone...")
            this.persistSelection(requestedDeviceId, selectedLabel)
            await this.populateInputDevices(requestedDeviceId)
            return
          }

          this.persistSelection("default", this.defaultOptionLabel)
          this.dispatchSelection("default")
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

      if (this.select && this.onSelectFocus) {
        this.select.removeEventListener("focus", this.onSelectFocus)
      }
    },

    dispatchSelection(deviceId) {
      window.dispatchEvent(new CustomEvent("open890:set-mic-input", {
        detail: {deviceId: deviceId || "default"}
      }))
    },

    persistSelection(deviceId, label) {
      const resolvedDeviceId = deviceId || "default"
      window.localStorage.setItem(this.storageKey, resolvedDeviceId)

      if (resolvedDeviceId === "default") {
        window.localStorage.removeItem(this.storageLabelKey)
        return
      }

      if (label && label.trim() !== "") {
        window.localStorage.setItem(this.storageLabelKey, label)
      }
    },

    async requestMicrophonePermission() {
      if (!navigator.mediaDevices || typeof navigator.mediaDevices.getUserMedia !== "function") {
        return {
          ok: false,
          message: "Microphone permissions are unavailable in this browser"
        }
      }

      try {
        const stream = await navigator.mediaDevices.getUserMedia({audio: true})
        stream.getTracks().forEach((track) => track.stop())
        return {ok: true}
      } catch (error) {
        if (error && error.name === "NotAllowedError") {
          return {ok: false, message: "Microphone permission denied"}
        }

        if (error && error.name === "NotFoundError") {
          return {ok: false, message: "No microphone available"}
        }

        if (error && error.name === "NotReadableError") {
          return {ok: false, message: "Microphone is busy or unavailable"}
        }

        if (error && error.name === "SecurityError") {
          return {ok: false, message: "Microphone access requires a secure browser context"}
        }

        return {
          ok: false,
          message: error && error.message ? error.message : "Unable to request microphone permission"
        }
      }
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

    async populateInputDevices(preferredDeviceId = null) {
      if (!this.select) {
        return
      }

      const savedDeviceId = preferredDeviceId || window.localStorage.getItem(this.storageKey) || "default"
      const savedDeviceLabel = window.localStorage.getItem(this.storageLabelKey) || ""

      if (!window.isSecureContext) {
        this.setOptions([{deviceId: "default", label: this.defaultOptionLabel}], savedDeviceId)
        this.select.disabled = true
        this.renderStatus("Use HTTPS to select microphone devices")
        return
      }

      if (!navigator.mediaDevices || typeof navigator.mediaDevices.enumerateDevices !== "function") {
        this.setOptions([{deviceId: "default", label: this.defaultOptionLabel}], savedDeviceId)
        this.select.disabled = true
        this.renderStatus("Microphone devices unavailable")
        return
      }

      try {
        const devices = await navigator.mediaDevices.enumerateDevices()
        const inputDevices = devices.filter((device) =>
          device.kind === "audioinput" && device.deviceId !== "default"
        )
        const hasNamedInputs = inputDevices.some(
          (device) => device.label && device.label.trim() !== ""
        )

        const options = [{deviceId: "default", label: this.defaultOptionLabel}]

        if (this.canPromptForMicInput && inputDevices.length > 0 && !hasNamedInputs) {
          options.push({
            deviceId: this.pickInputOptionValue,
            label: this.pickInputOptionLabel
          })
        }

        options.push(
          ...inputDevices.map((device, index) => {
            const label = device.label && device.label.trim() !== ""
              ? device.label
              : `Microphone ${index + 1}`

            return {deviceId: device.deviceId, label}
          })
        )

        let resolvedDeviceId = savedDeviceId
        let missingSavedDevice = false

        if (resolvedDeviceId !== "default" && !options.some((option) => option.deviceId === resolvedDeviceId)) {
          const labelMatch = savedDeviceLabel && savedDeviceLabel.trim() !== ""
            ? options.find((option) => option.deviceId !== "default" && option.label === savedDeviceLabel)
            : null

          if (labelMatch) {
            resolvedDeviceId = labelMatch.deviceId
            this.persistSelection(labelMatch.deviceId, labelMatch.label)
          } else {
            const fallbackLabel = savedDeviceLabel && savedDeviceLabel.trim() !== ""
              ? `${savedDeviceLabel} (reselect)`
              : "Saved microphone (reselect)"
            options.splice(1, 0, {deviceId: savedDeviceId, label: fallbackLabel})
            missingSavedDevice = true
          }
        }

        this.setOptions(options, resolvedDeviceId)
        this.select.disabled = options.length === 1 && !this.canPromptForMicInput

        if (missingSavedDevice) {
          this.renderStatus("Saved microphone not available. Re-authorize or choose it again.")
          return
        }

        const selectedDeviceId = this.select.value || "default"
        if (selectedDeviceId === this.pickInputOptionValue) {
          this.renderStatus("Select \"Enable microphone list...\" to choose a microphone")
          return
        }

        const selectedLabel = this.select.options[this.select.selectedIndex]
          ? this.select.options[this.select.selectedIndex].text
          : this.defaultOptionLabel
        this.persistSelection(selectedDeviceId, selectedLabel)
        this.dispatchSelection(selectedDeviceId)

        if (!hasNamedInputs && this.canPromptForMicInput && inputDevices.length > 0) {
          this.renderStatus("Select \"Enable microphone list...\" to choose a microphone")
        }
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
