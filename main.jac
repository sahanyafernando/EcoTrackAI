"""EcoTrack AI — authentication and organization verification milestone."""
import from endpoints { account, apply, edit_organization, organizations, review }
import from .frontend { app as ClientApp }

def:pub app -> JsxElement { <ClientApp/> }
