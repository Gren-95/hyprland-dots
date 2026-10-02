pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Run a command, collect its output, and say so when it fails. For the
// Process users that used to read stdout and silently ignore a non-zero exit
// (a broken script just left the panel empty). Fire-and-forget launches keep
// using startDetached().
//
//   Cmd.run(["bash", Paths.scripts + "/x.sh"], (ok, out, err) => { ... });
//
// `onDone` is optional and runs once, after the process has exited and its
// output has been read. Failures are always logged with console.warn.
Singleton {
    id: svc

    function run(cmd, onDone) {
        const job = runner.createObject(svc, { command: cmd, done: onDone });
        job.started = true;
        job.start();
    }

    // One job per call. Process takes no child objects, so the grace timer
    // lives on this wrapper next to it.
    Component {
        id: runner
        QtObject {
            id: job
            property var command: []
            property var done: null
            property int code: -1
            property bool exitSeen: false
            property bool outSeen: false
            property bool errSeen: false
            property bool finished: false

            function start() { proc.running = true; }
            function finish() {
                if (finished) return;
                finished = true;
                const ok = code === 0;
                if (!ok)
                    console.warn("[Cmd] " + command.join(" ") + " failed (exit " + code + ")"
                        + (err.text.trim() ? ": " + err.text.trim() : ""));
                if (done) done(ok, out.text, err.text);
                job.destroy();
            }
            // Exit and EOF on the pipes arrive in no fixed order, so finish
            // once all three are in; the timer covers a pipe that never
            // reports EOF.
            function maybeFinish() { if (exitSeen && outSeen && errSeen) finish(); }

            property Process proc: Process {
                command: job.command
                stdout: StdioCollector { id: out; onStreamFinished: { job.outSeen = true; job.maybeFinish(); } }
                stderr: StdioCollector { id: err; onStreamFinished: { job.errSeen = true; job.maybeFinish(); } }
                onExited: (exitCode) => {
                    job.code = exitCode;
                    job.exitSeen = true;
                    job.maybeFinish();
                    job.grace.start();
                }
                // A command that cannot be spawned never exits; stopping is
                // the only signal there is.
                onRunningChanged: if (!running && job.started) job.grace.start()
            }
            property bool started: false
            property Timer grace: Timer { interval: 100; onTriggered: job.finish() }
        }
    }
}
