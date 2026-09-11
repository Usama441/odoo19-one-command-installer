/* global SIP */

import { SessionRecorder } from "@voip/core/session_recorder";

import { _t } from "@web/core/l10n/translation";

export class Session {
    /** @type {import("@voip/core/call_service").CallService} */
    callService;
    /**
     * Only defined on sessions associated with an outbound call.
     *
     * @type {"trying"|"ringing"|"ok"|undefined}
     */
    inviteState;
    /** @type {boolean} */
    isMute = false;
    /** @type {SessionRecorder} */
    recorder;
    /**
     * The HTMLAudioElement through which the remote audio (remote peer's voice)
     * will be played.
     *
     * @type {HTMLAudioElement|null}
     */
    remoteAudio = null;
    /** @type {string|undefined} */
    transferTarget;
    /** @type {import("@voip/core/call_model").Call} */
    _call;
    /** @type {boolean} */
    _isOnHold = false;
    /**
     * The equivalent object from the SIP.js library.
     * Initially null for outbound calls.
     * null in demo mode.
     *
     * @type {SIP.Session|null}
     */
    _sipSession;

    constructor(call, sipSession = null) {
        if (!call) {
            throw new Error("Required argument 'call' is missing.");
        }
        this.callService = call.store.env.services["voip.call"];
        if (call.direction === "outgoing") {
            this.inviteState = "trying";
        }
        this._call = call;
        this.sipSession = sipSession;
        this.voip = call.store.env.services.voip;
    }

    /** @type {import("@voip/core/call_model").Call} */
    get call() {
        return this._call;
    }

    set call(_) {
        throw new Error("Redefining the call associated with a session is not allowed.");
    }

    get isOnHold() {
        return this._isOnHold;
    }

    set isOnHold(state) {
        if (this.sipSession) {
            this._requestHold(state);
        } else {
            this._isOnHold = state;
        }
    }

    get sipSession() {
        return this._sipSession;
    }

    set sipSession(sipSession) {
        if (this.sipSession) {
            throw new Error("Redefining sipSession is not allowed.");
        }
        this._sipSession = sipSession;
        if (!this._sipSession) {
            return;
        }
        this._sipSession.delegate = {
            onBye: (bye) => this._onBye(bye),
        };
        this._sipSession.stateChange.addListener((state) => this._onSessionStateChange(state));
    }

    /**
     * Starts recording the audio of the session.
     * Once the recording stops, the file is automatically uploaded.
     */
    record() {
        if (this.recorder) {
            console.warn("Session.record() called on a session that already had a recorder.");
            return;
        }
        if (!this.sipSession) {
            return; // no session in demo mode
        }
        this.recorder = new SessionRecorder(this.sipSession);
        this.recorder.start();
        this.recorder.file.then((recording) =>
            SessionRecorder.upload(`/voip/upload_recording/${this.call.id}`, recording)
        );
    }

    /**
     * Explicitly resets the source and stops playback of the remote audio to
     * ensure that it can be garbage-collected.
     */
    _cleanUpRemoteAudio() {
        if (!this.remoteAudio) {
            return;
        }
        this.remoteAudio.pause();
        this.remoteAudio.srcObject.getTracks().forEach((track) => track.stop());
        this.remoteAudio.srcObject = null;
        this.remoteAudio.load();
        this.remoteAudio = null;
    }

    /**
     * Triggered when receiving a BYE request. Useful to detect when the callee
     * of an outgoing call hangs up.
     *
     * @param {SIP.IncomingByeRequest} bye
     */
    _onBye({ incomingByeRequest: bye }) {
        if (!this.callService) {
            throw new Error("callService is not set.");
        }
        this.callService.end(this.call);
    }

    /**
     * Triggered when the state of the SIP.js session changes to Established.
     * Only triggered by actual RTC sessions (production mode).
     */
    _onSessionEstablished() {
        this._setUpRemoteAudio();
        this.sipSession.sessionDescriptionHandler.remoteMediaStream.onaddtrack = (
            mediaStreamTrackEvent
        ) => this._setUpRemoteAudio();
        if (this.voip.recordingPolicy === "always") {
            this.record();
        }
    }

    /** @param {SIP.SessionState} newState */
    _onSessionStateChange(newState) {
        switch (newState) {
            case SIP.SessionState.Initial:
                break;
            case SIP.SessionState.Establishing:
                break;
            case SIP.SessionState.Established:
                this._onSessionEstablished();
                break;
            case SIP.SessionState.Terminating:
                break;
            case SIP.SessionState.Terminated: {
                this._onSessionTerminated();
                break;
            }
            default:
                throw new Error(`Unknown session state: "${newState}".`);
        }
    }

    /**
     * Triggered when the state of the SIP.js session changes to Terminated.
     * Only triggered by actual RTC sessions (production mode).
     */
    _onSessionTerminated() {
        this._cleanUpRemoteAudio();
    }

    /**
     * Requests the remote peer to put the session on hold / resume it.
     *
     * @param {boolean} state `true` to put on hold, `false` to resume.
     */
    async _requestHold(state) {
        try {
            await this.sipSession.invite({
                requestDelegate: {
                    onAccept: () => {
                        this._isOnHold = state;
                    },
                },
                sessionDescriptionHandlerOptions: { hold: state },
            });
        } catch (error) {
            console.error(error);
            let errorMessage;
            if (state === true) {
                errorMessage = _t("Error putting the call on hold:");
            } else {
                errorMessage = _t("Error resuming the call:");
            }
            errorMessage += "\n\n" + error.message;
            this.voip.triggerError(errorMessage, { isNonBlocking: true });
        }
    }

    _setUpRemoteAudio() {
        const remoteAudio = new Audio();
        const remoteStream = new MediaStream();
        const receivers = this.sipSession.sessionDescriptionHandler.peerConnection.getReceivers();
        for (const { track } of receivers) {
            if (track) {
                remoteStream.addTrack(track);
            }
        }
        remoteAudio.srcObject = remoteStream;
        this._cleanUpRemoteAudio();
        this.remoteAudio = remoteAudio;
        remoteAudio.play();
    }
}
