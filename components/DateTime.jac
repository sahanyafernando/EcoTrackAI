"""Display persisted timestamps in the viewer's browser locale and timezone."""
def:pub DateTime(value: str) -> JsxElement {
    <time dateTime={value}>{new(Date, value).toLocaleString()}</time>
}
