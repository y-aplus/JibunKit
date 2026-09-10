# Web authentication ownership

Create one `MiniAppWebAuthenticationCoordinator` for the host presentation surface and give each Feature a runtime-owned `MiniAppWebAuthentication` connection. The coordinator does not replace `ASWebAuthenticationSession`; it supplies the host-level arbitration that the native per-request session does not express across Features.

```swift
let coordinator = MiniAppWebAuthenticationCoordinator()
let authentication = try runtime.makeWebAuthentication(
    context: context,
    coordinator: coordinator,
    presentationContextProvider: presentationProvider,
    prefersEphemeralWebBrowserSession: true
)

let request = try authentication.start(
    url: authorizationURL,
    callbackURLScheme: "example"
) { result in
    // This completion belongs only to context.id.
}
```

Retain the returned request while authentication is active. `request.cancel()` cancels exactly that request and delivers `Failure.cancelled` once; a later native callback is ignored. `authentication.cancel()` and runtime shutdown cancel only the request owned by that Feature. A second Feature receives `presentationBusy(owner:)` while another Feature owns the presentation surface, and may retry after the first completion or cancellation. A native `start()` rejection is delivered as `startRejected` and immediately releases the surface.

The Feature still owns its authorization URL, callback scheme, callback validation, OAuth state/PKCE handling, token exchange, and credentials. JibunKit neither invents an OAuth provider nor handles credentials. Supply a presentation context provider whose anchor belongs to the active host scene.

Apple documents `ASWebAuthenticationSession` as a request object initialized with its own completion handler, `start()` as a Boolean admission result, `cancel()` as cancellation of that session, and `presentationContextProvider` as the source of the presentation anchor. `prefersEphemeralWebBrowserSession` is only a request to avoid the shared browser session; the user may still be prompted. These native properties remain intact behind the ownership connection.

Provider-injection tests prove deterministic start/conflict/callback/cancel routing without displaying authentication UI or contacting an OAuth service. They do not prove the OS consent sheet, browser handoff, universal/custom-scheme callback delivery, or a real provider login. Validate those separately in an app with its registered callback and scene presentation anchor.

## Apple references

- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [start()](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/start())
- [cancel()](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/cancel())
- [presentationContextProvider](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/presentationcontextprovider)
- [prefersEphemeralWebBrowserSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/prefersephemeralwebbrowsersession)
