//
//  ReadyEvt.swift
//  DiscordAPI
//
//  Created by Vincent Kwok on 21/2/22.
//

import Foundation

/// The ready event palyoad for user accounts
public struct ReadyEvt: Decodable, GatewayData {
    // swiftlint:disable:next identifier_name
    public let v: Int
    public let user: CurrentUser
    public let users: [User]
    public let guilds: [Guild]
    public let session_id: String
    public let shard: [Int]? // Included for inclusivity, will not be used
    public let application: PartialApplication? // Discord doesn't send this to human clients
    public let user_settings: UserSettings? // Depreciated, no longer sent
    public let user_settings_proto: String? // Protobuf of user settings
    public let private_channels: [Channel] // Basically DMs
}

/// The ready event payload for bot accounts
public struct BotReadyEvt: Decodable, GatewayData {
    // swiftlint:disable:next identifier_name
    public let v: Int
    public let user: User
    public let guilds: [GuildUnavailable]
    public let session_id: String
    public let shard: [Int]? // Included for inclusivity, will not be used
    public let application: PartialApplication? // Discord doesn't send this to human clients
    public let user_settings: UserSettings? // Depreciated, no longer sent
    public let user_settings_proto: String? // Protobuf of user settings
    public let private_channels: [Channel] // Basically DMs
}
