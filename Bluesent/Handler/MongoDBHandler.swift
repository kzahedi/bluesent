//
//  MongoService.swift
//  Bluesent
//
//  Created by Keyan Ghazi-Zahedi on 24.12.24.
//

import Foundation
import MongoSwiftSync

class MongoDBHandler {
    private let client: MongoClient
    private var database: MongoDatabase
    public let posts: MongoCollection<ReplyTree>
    public let statistics: MongoCollection<DailyStats>
    
    init() throws {
        // Initialize MongoDB client
        client = try MongoClient("mongodb://localhost:27017")
        database = client.db("bluesent")
        posts = database.collection("posts", withType: ReplyTree.self)
        statistics = database.collection("statistics", withType: DailyStats.self)
        
        // Create unique index on _id
        // try posts.createIndex(["_id": 1], indexOptions: IndexOptions(unique: true))
    }
    
    public func saveFeedDocuments(documents: [ReplyTree]) throws -> Bool {
        var foundAll = true
        for document in documents {
            let r = try updateFeedDocument(document: document)
            foundAll = foundAll && r
        }
        return foundAll
    }
    
    public func updateFeedDocument(document:ReplyTree) throws -> Bool {
        let filter: BSONDocument = ["_id": .string(document._id)]
        var docForUpdate = document
        var found = false
        let xDays = UserDefaults.standard.integer(forKey: labelScrapingMinDaysForUpdate)
        
        let doc = try posts.findOne(filter) // if document is found, only update stats
        
        if doc != nil {
            docForUpdate.likeCount = doc!.likeCount
            docForUpdate.replyCount = doc!.replyCount
            docForUpdate.quoteCount = doc!.quoteCount
            docForUpdate.repostCount = doc!.repostCount
            docForUpdate.fetchedAt = Date()
            if docForUpdate.createdAt == nil && doc!.createdAt != nil {
                docForUpdate.createdAt = doc!.createdAt!
            }
            if docForUpdate.createdAt != nil && docForUpdate.createdAt!.isXDaysAgo(x: xDays){
                found = true
            }
        }
        
        let update: BSONDocument = ["$set": .document(try BSONEncoder().encode(docForUpdate))]
        try posts.updateOne(
            filter: filter,
            update: update,
            options: UpdateOptions(upsert: true)
        )
        return found
    }
    
    public func updateDailyStats(document:DailyStats) throws {
        let filter: BSONDocument = ["_id": .string(document._id)]
        let update: BSONDocument = ["$set": .document(try BSONEncoder().encode(document))]
        
        // Use updateOne with upsert to avoid duplicates
        try statistics.updateOne(
            filter: filter,
            update: update,
            options: UpdateOptions(upsert: true)
        )
    }
    
    public func getPostsPerDay(did:String, firstDate:Date? = nil, lastDate:Date?=nil) throws -> DailyStats? {
        var dailyStats = try statistics.findOne(["_id":BSON(stringLiteral: did)])
        
        if dailyStats == nil {
            return nil
        }
        
        if firstDate != nil && lastDate != nil {
            dailyStats!.postStats! = dailyStats!.postStats!
                .filter { $0.day >= firstDate! && $0.day <= lastDate! }
        }
        if firstDate != nil && lastDate == nil {
            dailyStats!.postStats! = dailyStats!.postStats!
                .filter { $0.day >= firstDate! }
        }
        if firstDate == nil && lastDate != nil {
            dailyStats!.postStats! = dailyStats!.postStats!
                .filter { $0.day <= lastDate! }
        }
        dailyStats!.postStats!.sort{ (($0.day).compare($1.day)) == .orderedDescending }
        
        return dailyStats!
    }
    
    
    deinit {
        cleanupMongoSwift()
    }
}
