impl ReportPanel.loadReports -> None {
    options: list[str] = [];
    loading = True;
    try {
        options = await report_categories();
        categories = options;
    } except Exception {
        feedback = "Unable to load categories. Retry loading the form.";
    } finally { loading = False; }
}

impl ReportPanel.confirmLocation -> None {
    lat = Number(latitude);
    lon = Number(longitude);
    if not latitude.strip() or not longitude.strip() or not Number.isFinite(lat)
        or not Number.isFinite(lon) or lat < -90 or lat > 90 or lon < -180 or lon > 180 {
        locationMessage = "Enter latitude from -90 to 90 and longitude from -180 to 180.";
        return;
    }
    confirmed = True;
    locationMessage = "Location confirmed. Choose Change location to replace it.";
}

impl ReportPanel.changeLocation -> None {
    gpsGeneration.current = (gpsGeneration.current or 0) + 1;
    confirmed = False;
    locationMessage = "Edit coordinates or request your current location, then confirm again.";
}

impl ReportPanel.locate -> None {
    if locating or confirmed or saving { return; }
    if not globalThis.navigator or not globalThis.navigator.geolocation {
        locationMessage = "Device location is unavailable. Enter coordinates manually, or retry in a browser with GPS support.";
        return;
    }
    locating = True;
    locationMessage = "Requesting device location…";
    gpsGeneration.current = (gpsGeneration.current or 0) + 1;
    generation = gpsGeneration.current;
    try {
        globalThis.navigator.geolocation.getCurrentPosition(
            lambda (position: any) {
                if gpsGeneration.current != generation or confirmed { return; }
                latitude = str(position.coords.latitude);
                longitude = str(position.coords.longitude);
                locating = False;
                locationMessage = "Location acquired. Review the coordinates and confirm before submitting.";
            },
            lambda (error: any) {
                if gpsGeneration.current != generation { return; }
                locating = False;
                if error.code == 1 {
                    locationMessage = "Location permission denied. Enable location access and retry, or enter coordinates manually.";
                } elif error.code == 3 {
                    locationMessage = "Location request timed out. Retry or enter coordinates manually.";
                } else {
                    locationMessage = "Location is unavailable. Retry or enter coordinates manually.";
                }
            },
            {"enableHighAccuracy": True, "timeout": 12000, "maximumAge": 0}
        );
    } except Exception {
        locating = False;
        locationMessage = "Could not request location. Retry or enter coordinates manually. GPS needs HTTPS or localhost.";
    }
}

impl ReportPanel.submit(e: FormEvent) -> None {
    e.preventDefault();
    if sendingRef.current or saving { return; }
    if not confirmed or locating { feedback = "Confirm your location before submitting."; return; }
    if not description.strip() or category not in categories {
        feedback = "Enter a description and select a category.";
        return;
    }
    sendingRef.current = True;
    saving = True;
    feedback = "";
    saved: ReportView | None = None;
    try {
        if not requestRef.current {
            requestRef.current = globalThis.crypto.randomUUID() if globalThis.crypto and globalThis.crypto.randomUUID else str(Date.now()) + "-" + str(Math.random());
        }
        saved = await create_report(description=description, category=category,
            latitude=Number(latitude), longitude=Number(longitude), location_text=locationText,
            submission_id=requestRef.current or "");
        onSaved(saved);
        description = "";
        category = "";
        latitude = "";
        longitude = "";
        locationText = "";
        confirmed = False;
        locationMessage = "";
        requestRef.current = "";
        feedback = "Report received. Your observation has been saved for Central Authority review. Related-incident analysis is not available yet.";
    } except Exception as error {
        feedback = "Could not save report: " + str(error) + " Your entries have been kept; retry or refresh My Reports if the connection was interrupted.";
    } finally {
        sendingRef.current = False;
        saving = False;
    }
}
