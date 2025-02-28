open Prelude
open Conf

let default_state = Markdown.default_state

let empty_references = Reference.empty_parsed_t

let default_config =
  { toc = true
  ; parse_outline_only = false
  ; heading_number = true
  ; keep_line_break = false
  ; format = Conf.Markdown
  ; heading_to_list = true
  ; exporting_keep_properties = false
  ; inline_type_with_pos = false
  ; export_md_indent_style = Spaces
  ; export_md_remove_options = []
  ; hiccup_in_block = true
  }

let attr ?(uri = "") local value : Xmlm.attribute = ((uri, local), value)

let tag name attrs : Xmlm.tag = (("", name), attrs)

(* only concat Leaf list, ignore Branch elem *)
let zipl_to_string_list l =
  List.map
    (fun e ->
      match e with
      | Zip.Leaf s -> s
      | Zip.Branch _ -> "")
    l

let outline_frag ?(childs = []) ?note text : string Zip.l Xmlm.frag =
  let text_attr = attr "text" text in
  let attrs =
    match note with
    | None
    | Some [] ->
      [ text_attr ]
    | Some note' -> [ text_attr; attr "_note" (String.concat "\n" note') ]
  in
  `El ((("", "outline"), attrs), childs)

let collect_outline_note_part (l : string Zip.l list) =
  let rec aux r l =
    let note_part = r in
    match l with
    | [] -> (r, [])
    | (Zip.Leaf _ as h) :: t -> aux (h :: note_part) t
    | Zip.Branch _ :: _ as rest -> (List.rev note_part, rest)
  in
  aux [] l

let rec plain_tree_to_frag
    (plain_tree : Markdown_transformer.String_Tree_Value.t) :
    string Zip.l Xmlm.frag =
  let open Zip in
  match plain_tree with
  | Leaf s -> outline_frag s
  | Branch [] -> `Data ""
  | Branch (Leaf h :: t) ->
    let note_part, rest = collect_outline_note_part t in
    let note_part_string_list = zipl_to_string_list note_part in
    outline_frag ~childs:rest ~note:note_part_string_list h
  | Branch [ (Branch _ as e) ] -> plain_tree_to_frag e
  | Branch (Branch _ :: _ as l) -> outline_frag ~childs:l ""

let output_tree_type o tree = Xmlm.output_tree plain_tree_to_frag o tree

type output_header = { title : string }

let output_with_header o { title } tree =
  let open Xmlm in
  output o (`Dtd None);
  output o (`El_start (tag "opml" [ attr "version" "2.0" ]));
  output o (`El_start (tag "head" []));
  output o (`El_start (tag "title" []));
  output o (`Data title);
  (* title *) output o `El_end;
  (* head *) output o `El_end;
  (* body *) output o (`El_start (tag "body" []));
  let _ =
    match tree with
    | Zip.Leaf _ -> output_tree_type o tree
    | Zip.Branch l -> List.iter (output_tree_type o) l
  in
  (* body *)
  output o `El_end;
  (* opml *) output o `El_end

let blocks refs tl title output_buf =
  let open Tree_type in
  of_blocks tl
  |> replace_embed_and_refs ~refs
  |> replace_heading_with_paragraph |> to_value
  |> Markdown_transformer.String_Tree_Value.of_value ~config:default_config
  |> output_with_header output_buf { title }

module OPMLExporter = struct
  let name = "opml"

  let default_filename = change_ext "opml"

  let export ~refs _config (doc : Document.t) output =
    let open Option in
    let refs =
      refs |? Reference.{ parsed_embed_blocks = []; parsed_embed_pages = [] }
    in
    let title = doc.filename |? (doc.title |? "untitled") in
    let output_buf = Xmlm.make_output ~indent:(Some 2) (`Channel output) in
    blocks refs doc.blocks title output_buf
end
