import from .Icon { Icon }

def:pub PlannedPage(title: str, description: str, icon: str = "leaf") -> JsxElement {
    <section className="planned-state">
        <span className="planned-icon"><Icon name={icon}/></span>
        <span className="badge planned">Not implemented yet</span>
        <h2>{title}</h2><p>{description}</p>
    </section>
}
