//
//  APIRequest.swift
//  Native Discord
//
//  Created by Vincent Kwok on 21/2/22.
//

import Foundation

/// Utility wrappers for easy request-making
public extension DiscordREST {
    enum RequestError: Error {
        case unexpectedResponseCode(_ code: Int)
        case invalidResponse
        case superEncodeFailure
        case jsonEncodingError
        case jsonDecodingError(error: DecodingError)
        case jsonDecodingError(genericError: Error)
        case genericError(reason: String)
    }

    /// The few supported request methods
    enum RequestMethod: String {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
        case patch = "PATCH"
    }

    /// Make a Discord REST API request
    ///
    /// Low level method for Discord API requests, meant to be as generic
    /// as possible. You should call other wrapper methods like `getReq()`,
    /// `postReq()`, `deleteReq()`, etc. where possible instead.
    ///
    /// - Parameters:
    ///   - path: API endpoint path relative to `GatewayConfig.restBase`
    ///   - query: Array of URL query items
    ///   - attachments: URL of file attachments, for messages with attachments.
    ///   Sends a request of type `multipart/form-data` if there are attachments,
    ///   otherwise a `application/json` request.
    ///   - body: Request body, should be a JSON string
    ///   - method: Method for the request
    ///   (currently `.get`, `.post`, `.delete` or `.patch`)
    ///
    /// - Returns: Raw `Data` of response, or nil if the request failed
    func makeRequest(
        path: String,
        query: [URLQueryItem] = [],
        attachments: [URL] = [],
        body: Data? = nil,
        method: RequestMethod = .get
    ) async -> Result<Data, RequestError> {
        assert(token != nil, "Token should not be nil. Please set a token before using the REST API.")
        let token = token! // Force unwrapping is appropriete here

        Self.log.trace("Making request", metadata: [
            "method": "\(method)",
            "path": "\(path)"
        ])

        let apiURL = DiscordKitConfig.default.restBase.appendingPathComponent(path, isDirectory: false)

        // Add query params (if any)
        var urlBuilder = URLComponents(url: apiURL, resolvingAgainstBaseURL: true)!
        urlBuilder.queryItems = query
        let reqURL = urlBuilder.url!

        // Create URLRequest and set headers
        var req = URLRequest(url: reqURL)
        req.httpMethod = method.rawValue
        req.setValue(DiscordKitConfig.default.isBot ? "Bot \(token)" : token, forHTTPHeaderField: "authorization")
        req.setValue(DiscordKitConfig.default.baseURL.absoluteString, forHTTPHeaderField: "origin")

        // These headers are to match headers present in actual requests from the official client
        // req.setValue("?0", forHTTPHeaderField: "sec-ch-ua-mobile") // The day this runs on iOS...
        // req.setValue("macOS", forHTTPHeaderField: "sec-ch-ua-platform") // We only run on macOS
        // The top 2 headers are only sent when running in browsers
        req.setValue(DiscordKitConfig.default.userAgent, forHTTPHeaderField: "user-agent")
        req.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
        req.setValue("same-origin", forHTTPHeaderField: "sec-fetch-site")
        req.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")

        req.setValue(Locale.englishUS.rawValue, forHTTPHeaderField: "x-discord-locale")
        req.setValue("bugReporterEnabled", forHTTPHeaderField: "x-debug-options")
        guard let superEncoded = try? DiscordREST.encoder.encode(DiscordKitConfig.default.properties) else {
            assertionFailure("Couldn't encode super properties for request")
            return .failure(.superEncodeFailure)
        }
        req.setValue(superEncoded.base64EncodedString(), forHTTPHeaderField: "x-super-properties")

        if !attachments.isEmpty {
            // Exact boundary format used by Electron (WebKit) in Discord Desktop
            let boundary = "----WebKitFormBoundary\(String.random(count: 16))"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
            req.httpBody = DiscordREST.createMultipartBody(with: body, boundary: boundary, attachments: attachments)
        } else if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = body
        }

        // Make request
        guard let (data, response) = try? await DiscordREST.session.data(for: req),
              let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }
        guard httpResponse.statusCode / 100 == 2 else { // Check if status code is 2**
            Self.log.error("Response status code not 2xx", metadata: ["res.statusCode": "\(httpResponse.statusCode)"])
            Self.log.debug("Raw response: \(String(decoding: data, as: UTF8.self))")
            return .failure(.unexpectedResponseCode(httpResponse.statusCode))
        }

        return .success(data)
    }

    /// Make a `GET` request to the Discord REST API
    ///
    /// Wrapper method for `makeRequest()` to make a GET request.
    ///
    /// - Parameters:
    ///   - path: API endpoint path relative to `GatewayConfig.restBase`
    ///  (passed canonically to `makeRequest()`)
    ///   - query: Array of URL query items (passed canonically to `makeRequest()`)
    ///
    /// - Returns: Struct of response conforming to Decodable, or nil
    /// if the request failed or the response couldn't be JSON-decoded.
    func getReq<T: Decodable>(
        path: String,
        query: [URLQueryItem] = []
    ) async -> Result<T, RequestError> {
        // This helps debug JSON decoding errors
        let resp = await makeRequest(path: path, query: query)
        switch resp {
        case .failure(let err):
            return .failure(err)
        case .success(let respData):
            do {
                return .success(try DiscordREST.decoder.decode(T.self, from: respData))
            } catch let decodingError as DecodingError {
                return .failure(.jsonDecodingError(error: decodingError))
            } catch {
                return .failure(.jsonDecodingError(genericError: error))
            }
        }
    }

    /// Make a `POST` request to the Discord REST API
    func postReq<D: Decodable, B: Encodable>(
        path: String,
        body: B? = nil,
        attachments: [URL] = []
    ) async -> Result<D, RequestError> {
        let payload = body != nil ? try? DiscordREST.encoder.encode(body) : nil
        switch await makeRequest(
            path: path,
            attachments: attachments,
            body: payload,
            method: .post
        ) {
        case .success(let respData):
            do {
                return .success(try DiscordREST.decoder.decode(D.self, from: respData))
            } catch let decodingError as DecodingError {
                return .failure(.jsonDecodingError(error: decodingError))
            } catch {
                return .failure(.jsonDecodingError(genericError: error))
            }
        case .failure(let err): return .failure(err)
        }
    }

    /// Make a `POST` request to the Discord REST API
    ///
    /// For endpoints that returns a 204 empty response
    func postReq<B: Encodable>(
        path: String,
        body: B
    ) async throws {
        let payload = try DiscordREST.encoder.encode(body)
        _ = try await makeRequest(
            path: path,
            body: payload,
            method: .post
        ).get()
    }

    /// Make a `POST` request to the Discord REST API, for endpoints
    /// that both require no payload and returns a 204 empty response
    func emptyPostReq(path: String) async throws {
        _ = try await makeRequest(
            path: path,
            body: nil,
            method: .post
        ).get()
    }

    /// Make a `DELETE` request to the Discord REST API
    func deleteReq(path: String) async throws {
        _ = try await makeRequest(path: path, method: .delete).get()
    }

    /// Make a `PATCH` request to the Discord REST API
    ///
    /// Getting the response from PATCH requests aren't implemented
    /// as their response is usually not required
    func patchReq<B: Encodable>(
        path: String,
        body: B
    ) async throws {
        let payload = try? DiscordREST.encoder.encode(body)
        _ = try await makeRequest(
            path: path,
            body: payload,
            method: .patch
        ).get()
    }
}
