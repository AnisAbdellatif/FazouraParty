# The uploads volume is a directory on disk, and tests write real files to it.
# Nothing cleared it, so it grew by a few files every run — and because uploads
# are content-addressed, a fixture whose bytes matched something an earlier run
# had already stored added no file at all. That made "nothing reached the
# uploads volume" assertions pass or fail depending on what was left over from
# yesterday. The directory belongs to the test run, so the test run starts it
# empty.
File.rm_rf!(Fazoura.Uploads.dir())

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Fazoura.Repo, :manual)
