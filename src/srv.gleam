import gleam/erlang/os
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/string_builder

import argv
import fmglee
import mist
import simplifile
import wisp

const usage = "
srv [OPTIONS]

Options:
  -p --port: The port to serve on, defaults to 9999
  -h --help: Show this message and exit
"

type DirItem {
  DirItem(name: String, path: String)
}

fn error_to_resp(e: simplifile.FileError) -> wisp.Response {
  simplifile.describe_error(e)
  |> string_builder.from_string
  |> wisp.html_response(500)
}

fn path_sep() -> String {
  case os.family() {
    os.WindowsNt -> "\\"
    _ -> "/"
  }
}

fn load_file(path: String) -> wisp.Response {
  case simplifile.read(path) {
    Ok(data) -> {
      let body = string_builder.from_string(data)

      wisp.response(200)
      |> wisp.set_body(wisp.Text(body))
    }
    Error(simplifile.Enoent) -> wisp.not_found()
    Error(e) -> error_to_resp(e)
  }
}

fn build_dir_response(files: List(DirItem)) -> wisp.Response {
  let links =
    list.map(files, fn(f) {
      fmglee.new("<p><a href='%s'>%s</a><p>")
      |> fmglee.s(f.path)
      |> fmglee.s(f.name)
      |> fmglee.build
    })
    |> string.join("\n")

  fmglee.new("<body>%s</body>")
  |> fmglee.s(links)
  |> fmglee.build
  |> string_builder.from_string
  |> wisp.html_response(200)
}

fn load_dir(path: String) -> wisp.Response {
  let sep = path_sep()

  case simplifile.read_directory(path) {
    Ok(files) -> {
      files
      |> list.map(fn(f: String) { { path <> sep <> f } |> into_file })
      |> build_dir_response()
    }
    Error(e) -> error_to_resp(e)
  }
}

fn serve_content(path: String) -> wisp.Response {
  case simplifile.is_directory(path) {
    Ok(True) -> load_dir(path)
    Ok(False) -> load_file(path)
    Error(e) -> error_to_resp(e)
  }
}

fn build_path(path: List(String)) -> String {
  [".", ..path]
  |> string.join(path_sep())
}

fn into_file(path: String) -> DirItem {
  let sep = path_sep()

  let name =
    string.split(path, sep)
    |> list.last()
    |> result.unwrap(".")

  let path = case string.split(path, sep) {
    [_, _, _, ..] ->
      string.split(path, sep)
      |> list.reverse
      |> list.take(2)
      |> list.reverse
      |> string.join(sep)
    _ -> path
  }

  DirItem(name: name, path: path)
}

fn handler(req: wisp.Request) -> wisp.Response {
  use <- wisp.log_request(req)

  wisp.path_segments(req)
  |> build_path
  |> serve_content
}

fn serve(port: Int) {
  wisp.configure_logger()
  let secret_base_key = wisp.random_string(64)

  let assert Ok(_) =
    handler(_)
    |> wisp.mist_handler(secret_base_key)
    |> mist.new
    |> mist.port(port)
    |> mist.start_http

  process.sleep_forever()
}

pub fn main() {
  case argv.load().arguments {
    [] -> serve(9999)
    ["--port", port] | ["-p", port] -> {
      case int.parse(port) {
        Ok(port) -> serve(port)
        Error(Nil) -> io.print_error("Invalid port: " <> port)
      }
    }
    ["--help"] | ["-h"] -> usage |> io.println
    _ -> usage |> io.println_error
  }
}
