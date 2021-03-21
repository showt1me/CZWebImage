//
//  CZHttpFileDownloader.swift
//  CZWebImage
//
//  Created by Cheng Zhang on 1/20/16.
//  Copyright © 2016 Cheng Zhang. All rights reserved.
//

import UIKit
import CZUtils
import CZNetworking
import CZHttpFileCache

private var kvoContext: UInt8 = 0

public typealias CZHttpFileDownloaderCompletion = (_ image: UIImage?, _ error: Error?, _ fromCache: Bool) -> Void

/**
 Asynchronous image downloading class on top of OperationQueue
 */
public class CZHttpFileDownloader: NSObject {
    public static let shared = CZHttpFileDownloader()
    private let imageDownloadQueue: OperationQueue
    private let imageDecodeQueue: OperationQueue
    private enum Constant {
        static let imageDownloadQueueName = "com.tony.image.download"
        static let imageDecodeQueueName = "com.tony.image.decode"
    }
    
    public override init() {
        imageDownloadQueue = OperationQueue()
        imageDownloadQueue.name = Constant.imageDownloadQueueName
        imageDownloadQueue.qualityOfService = .userInteractive
        imageDownloadQueue.maxConcurrentOperationCount = CZWebImageConstants.downloadQueueMaxConcurrent
        
        imageDecodeQueue = OperationQueue()
        imageDownloadQueue.name = Constant.imageDecodeQueueName
        imageDecodeQueue.maxConcurrentOperationCount = CZWebImageConstants.decodeQueueMaxConcurrent
        super.init()
        
        if CZWebImageConstants.shouldObserveOperations {
            imageDownloadQueue.addObserver(self, forKeyPath: CZWebImageConstants.kOperations, options: [.new, .old], context: &kvoContext)
        }
    }
    
    deinit {
        if CZWebImageConstants.shouldObserveOperations {
            imageDownloadQueue.removeObserver(self, forKeyPath: CZWebImageConstants.kOperations)
        }
        imageDownloadQueue.cancelAllOperations()
    }
    
    public func downloadImage(with url: URL?,
                       cropSize: CGSize? = nil,
                       priority: Operation.QueuePriority = .normal,
                       completion: @escaping CZHttpFileDownloaderCompletion) {
        guard let url = url else { return }
        cancelDownload(with: url)
        
        let operation = ImageDownloadOperation(url: url,
                                               progress: nil,
                                               success: { [weak self] (task, data) in
            guard let `self` = self, let data = data else {
                completion(nil, WebImageError.invalidData, false)
                return
            }
            // Decode/crop image in decode OperationQueue
            self.imageDecodeQueue.addOperation {
                guard let image = UIImage(data: data) else {
                    completion(nil, WebImageError.invalidData, false)
                    return
                }
                let (outputImage, ouputData) = self.cropImageIfNeeded(image, data: data, cropSize: cropSize)
                CZImageCache.shared.setCacheFile(withUrl: url, data: ouputData)
                
                // Call completion on mainQueue
                MainQueueScheduler.async {
                    completion(outputImage, nil, false)
                }
            }
        }, failure: { (task, error) in
            completion(nil, error, false)
        })
        operation.queuePriority = priority
        imageDownloadQueue.addOperation(operation)
    }
    
    @objc(cancelDownloadWithURL:)
    public func cancelDownload(with url: URL?) {
        guard let url = url else { return }
        
        let cancelIfNeeded = { (operation: Operation) in
            if let operation = operation as? ImageDownloadOperation,
                operation.url == url {
                operation.cancel()
            }
        }
        imageDownloadQueue.operations.forEach(cancelIfNeeded)
    }
}

// MARK: - Private methods

private extension CZHttpFileDownloader {
    
    func cropImageIfNeeded(_ image: UIImage, data: Data, cropSize: CGSize?) -> (image: UIImage, data: Data?) {
        guard let cropSize = cropSize, cropSize != .zero else {
            return (image, data)
        }
        let croppedImage = image.crop(toSize: cropSize)
        return (croppedImage, croppedImage.pngData())
    }
    
}

// MARK: - KVO Delegation

extension CZHttpFileDownloader {
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &kvoContext,
            let object = object as? OperationQueue,
            let keyPath = keyPath,
            keyPath == CZWebImageConstants.kOperations else {
                return
        }
        if object === imageDownloadQueue {
            CZUtils.dbgPrint("[CZHttpFileDownloader] Queued tasks: \(object.operationCount)")
        }
    }
}
