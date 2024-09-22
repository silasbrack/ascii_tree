import birl
import gleam/io
import gleam/list
import gleam/regex.{type Regex}
import gleam/result
import gleam/string
import simplifile.{Enotdir}

pub type StringOrRegex {
  AString(string: String)
  ARegex(regex: Regex)
}

pub type Params {
  Params(ignore: List(StringOrRegex), width: Int)
}

pub fn main() {
  let assert Ok(my_regex) = regex.from_string(".*\\.toml")

  let functions = list.repeat(render_tree, times: 10)
  let times =
    list.map(functions, fn(my_fn) {
      let t0 = birl.now()
      my_fn(".", Params(ignore: [], width: 2))
      let elapsed = birl.difference(birl.now(), t0)
      elapsed
    })
  let assert [first, second, ..rest] = times
  io.debug(rest)
}

fn do_last_map(list: List(a), fun: fn(a, Bool) -> b, acc: List(b)) -> List(b) {
  case list {
    [] -> list.reverse(acc)
    [x] -> do_last_map([], fun, [fun(x, True), ..acc])
    [x, ..xs] -> do_last_map(xs, fun, [fun(x, False), ..acc])
  }
}

fn last_map(list: List(a), fun: fn(a, Bool) -> b) -> List(b) {
  do_last_map(list, fun, [])
}

fn format_values(
  text: String,
  depth: Int,
  name: String,
  is_last: List(Bool),
  params: Params,
) -> String {
  let width = params.width
  case depth {
    0 -> name
    _ -> {
      let assert Ok(#(symbol, is_last_corrected)) = case is_last {
        [True, ..rest] -> Ok(#("└" <> string.repeat("─", width - 1), rest))
        [False, ..rest] -> Ok(#("├" <> string.repeat("─", width - 1), rest))
        _ -> Error("")
      }
      let is_last_reversed = list.reverse(is_last_corrected)
      text
      <> "\n"
      <> {
        string.concat(
          list.map(is_last_reversed, fn(x) {
            case x {
              True -> " " <> string.repeat(" ", width - 1)
              False -> "│" <> string.repeat(" ", width - 1)
            }
          }),
        )
      }
      <> symbol
      <> name
    }
  }
}

fn sort_fn(children) {
  list.sort(children, string.compare)
}

fn render_tree_inner_old(
  text: String,
  path: String,
  depth: Int,
  name: String,
  siblings: List(String),
  is_last: List(Bool),
  params: Params,
) {
  let ignored =
    list.any(params.ignore, fn(x) {
      case x {
        ARegex(r) -> regex.check(r, name)
        AString(s) -> s == name
      }
    })
  let text = case ignored {
    True -> format_values(text, depth, name, is_last, params)
    False -> {
      let contents = simplifile.read_directory(path <> "/" <> name)
      case contents {
        Ok(values) ->
          case sort_fn(values) {
            // Empty folder
            [] -> format_values(text, depth, name, is_last, params)
            // One child
            [first_child] ->
              render_tree_inner_old(
                format_values(text, depth, name, is_last, params),
                path <> "/" <> name,
                depth + 1,
                first_child,
                [],
                [True, ..is_last],
                params,
              )
            // Some children
            [first_child, ..rest_child] ->
              render_tree_inner_old(
                format_values(text, depth, name, is_last, params),
                path <> "/" <> name,
                depth + 1,
                first_child,
                rest_child,
                [False, ..is_last],
                params,
              )
          }
        Error(err) ->
          case err {
            // File
            Enotdir -> format_values(text, depth, name, is_last, params)
            // Error
            _ -> text <> "\nERROR: " <> name
          }
      }
    }
  }
  case siblings {
    // No more siblings
    [] -> text
    // One sibling
    [first_sibling] ->
      render_tree_inner_old(
        text,
        path,
        depth,
        first_sibling,
        [],
        {
          let assert [_, ..rest] = is_last
          [True, ..rest]
        },
        params,
      )
    // Some siblings
    [first_sibling, ..rest_sibling] ->
      render_tree_inner_old(
        text,
        path,
        depth,
        first_sibling,
        rest_sibling,
        is_last,
        params,
      )
  }
}

fn render_tree_old(root_folder: String, params: Params) {
  render_tree_inner_old("", root_folder, 0, root_folder, [], [], params)
}

type Node {
  Node(path: String, name: String, depth: Int, is_last: List(Bool))
}

fn render_tree_inner(text: String, backlog: List(Node), params: Params) {
  case backlog {
    [] -> text
    [first, ..rest] -> {
      let ignored =
        list.any(params.ignore, fn(x) {
          case x {
            ARegex(r) -> regex.check(r, first.name)
            AString(s) -> s == first.name
          }
        })

      let children = case ignored {
        False -> {
          let current_path = first.path <> "/" <> first.name
          result.unwrap(simplifile.read_directory(current_path), [])
          |> sort_fn
          |> last_map(fn(x, is_last) {
            Node(current_path, x, first.depth + 1, [is_last, ..first.is_last])
          })
        }
        True -> []
      }
      render_tree_inner(
        format_values(text, first.depth, first.name, first.is_last, params),
        list.append(children, rest),
        params,
      )
    }
  }
}

fn render_tree(root_folder: String, params: Params) {
  render_tree_inner("", [Node(root_folder, root_folder, 0, [])], params)
}
