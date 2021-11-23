//
//  File.swift
//  
//
//  Created by SatGatLee on 2021/11/16.
//

import Foundation
import EosioSwift
import PromiseKit

let emptyResult: Promise<DIDResolutionResult> = Promise<DIDResolutionResult>.value(DIDResolutionResult())
let emptyDocument: Promise<DIDDocument> = Promise<DIDDocument>.value(DIDDocument())
let emptyResolvedDocument: Promise<ResolvedDIDDocument> = Promise<ResolvedDIDDocument>.value(ResolvedDIDDocument())

public func generateRandomBytes(bytes: Int) -> Data? {

    var keyData = Data(count: bytes)
    let result = keyData.withUnsafeMutableBytes {
        SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!)
    }
    if result == errSecSuccess {
      return keyData
    } else {
        print("Problem generating random bytes")
        return nil
    }
}

public func iPrint(_ objects:Any... , filename:String = #file,_ line:Int = #line, _ funcname:String = #function){ //debuging Print
  #if DEBUG
  let dateFormatter = DateFormatter()
  dateFormatter.dateFormat = "HH:mm:ss:SSS"
  let file = URL(string:filename)?.lastPathComponent.components(separatedBy: ".").first ?? ""
  print("💦info 🦋\(dateFormatter.string(from:Date())) 🌞\(file) 🍎line:\(line) 🌹\(funcname)🔥",terminator:"")
  for object in objects{
    print(object, terminator:"")
  }
  print("\n")
  #endif
}
