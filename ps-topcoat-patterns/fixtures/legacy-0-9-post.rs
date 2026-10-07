// src/app/posts/post_id.rs — Topcoat 0.9 module. Upgrade target: Topcoat 0.10.
// Module-routed: this file is meant to serve /posts/{post_id} and
// /posts/{post_id}/comments/{comment_id}. Relies on 0.9 behavior removed in
// 0.10: `path_param!` making the module segment dynamic, `str::len()` as f64,
// and a hand-written runtime script tag. Navigation uses plain anchors.

use topcoat::{
    Result,
    context::Cx,
    router::{href, page, path_param},
    runtime::{Event, SCRIPT, expr, signal},
    view::{View, view},
};

path_param!(pub post_id: u64, error = not_found);
path_param!(pub comment_id: u64, error = not_found);

#[page]
pub async fn page(cx: &Cx) -> Result<impl View> {
    let id = *path_param::<PostId>(cx)?;
    let draft = signal(cx, String::new);
    let too_long = expr!(draft.get().len() > 280.0);

    Ok(view! {
        <!DOCTYPE html>
        <html>
            <head>
                <script type="module" src=(SCRIPT)></script>
            </head>
            <body>
                <nav>
                    <a href=(href!(super::page))>"All posts"</a>
                    <a href=(href!(comment, PostId(id), CommentId(1)))>"First comment"</a>
                </nav>
                <h1>"Post " (id)</h1>
                <textarea :value=$(draft.get()) @input=$(|e: Event| draft.set(e.target.value))></textarea>
                <p :hidden=$(!too_long)>"Too long"</p>
            </body>
        </html>
    })
}

#[page("./comments/{comment_id}")]
pub async fn comment(cx: &Cx) -> Result<impl View> {
    let post_id = *path_param::<PostId>(cx)?;
    let comment_id = *path_param::<CommentId>(cx)?;
    Ok(view! { <p>"Post " (post_id) ", comment " (comment_id)</p> })
}
