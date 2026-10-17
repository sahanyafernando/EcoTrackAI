"""Small code-native outline icons; no external icon or image dependency."""
def:pub Icon(name: str) -> JsxElement {
    paths = {
        "leaf": "M20 4C10 3 3 7 5 14c2 7 12 7 15-10ZM5 20 15 10",
        "overview": "M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z",
        "reports": "M7 3h10l3 3v15H4V3h3ZM8 9h8M8 13h8M8 17h5",
        "pin": "M20 10c0 6-8 11-8 11S4 16 4 10a8 8 0 1 1 16 0ZM12 7v6M9 10h6",
        "organization": "M4 21V7l8-4 8 4v14M2 21h20M8 9h1M15 9h1M8 13h1M15 13h1M10 21v-4h4v4",
        "incidents": "M12 3 2 21h20L12 3ZM12 9v5M12 17v1",
        "people": "M3 21v-3c0-4 10-4 10 0v3M8 4a3 3 0 1 1 0 6 3 3 0 0 1 0-6ZM16 4a3 3 0 0 1 0 6M16 14c4 0 5 2 5 4v3",
        "person": "M5 21v-3c0-6 14-6 14 0v3M12 3a4 4 0 1 1 0 8 4 4 0 0 1 0-8Z",
        "activity": "M2 12h5l3-8 4 16 3-8h5",
        "audit": "M12 3 3 7v5c0 5 9 10 9 10s9-5 9-10V7l-9-4ZM8 12l3 3 5-6",
        "arrow": "M4 12h16M14 6l6 6-6 6",
        "logout": "M9 3H3v18h6M9 12h12M16 7l5 5-5 5",
        "menu": "M3 6h18M3 12h18M3 18h18"
    };
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d={paths.get(name, paths["leaf"])}/>
    </svg>
}
