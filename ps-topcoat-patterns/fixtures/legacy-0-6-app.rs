// Topcoat 0.6-era app module. Upgrade target: Topcoat 0.10.
// Uses APIs removed in 0.7-0.10: `-> Result` views, `slot: Result`,
// `child: View`, `#[component(boxed)]`, the `signal x = v;` DSL,
// component `key:` props, and `.procedure()` / `.shard()` registration.

use topcoat::{
    Result,
    context::Cx,
    router::{
        Router, RouterBuilderDiscoverExt, StatusCode,
        error::NotFoundError,
        layout, page,
    },
    runtime::{Event, procedure, shard},
    view::{View, component, view},
};

pub struct Post {
    pub id: u64,
    pub title: String,
}

pub struct Comment {
    pub body: String,
    pub replies: Vec<Comment>,
}

async fn load_posts(_cx: &Cx) -> Result<Vec<Post>> {
    Ok(vec![Post { id: 1, title: "Hello".to_owned() }])
}

pub fn router() -> Router {
    Router::builder()
        .discover()
        .procedure(like)
        .shard(search_results)
        .build()
}

#[layout("/")]
async fn root_layout(slot: Result) -> Result {
    let content = match slot {
        Err(error) if error.downcast_ref::<NotFoundError>().is_some() => view! {
            (StatusCode::NOT_FOUND)
            <h1>"Page not found"</h1>
        },
        content => content,
    }?;

    view! {
        <!DOCTYPE html>
        <html>
            <head>
                topcoat::dev::script()
                topcoat::runtime::script()
            </head>
            <body>(content)</body>
        </html>
    }
}

#[page("/")]
async fn home(cx: &Cx) -> Result {
    let posts = load_posts(cx).await?;
    view! {
        signal query = String::new();

        <input @input=$(|e: Event| query.set(e.target.value))>
        search_results(query: $(query.get()))

        for post in posts {
            card(key: post.id, title: &post.title,
                <button @click=$(async |_e| { like(post.id).await; })>"Like"</button>
            )
        }
    }?
}

#[component]
async fn card(title: &str, child: View) -> Result {
    view! {
        <article>
            <h2>(title)</h2>
            (child)
        </article>
    }
}

#[component(boxed)]
async fn comment_thread(comment: &Comment) -> Result {
    view! {
        <li>
            (&comment.body)
            <ul>
                for reply in &comment.replies {
                    comment_thread(comment: reply)
                }
            </ul>
        </li>
    }
}

#[shard]
async fn search_results(cx: &Cx, query: String) -> Result {
    let posts = load_posts(cx).await?;
    view! {
        <ul>
            for post in posts {
                if post.title.contains(&query) {
                    <li>(post.title)</li>
                }
            }
        </ul>
    }
}

#[procedure]
async fn like(post_id: u64) -> Result<bool> {
    Ok(post_id > 0)
}
