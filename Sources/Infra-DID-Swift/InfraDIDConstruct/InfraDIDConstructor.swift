//
//  File.swift
//  
//
//  Created by SatGatLee on 2021/11/11.
//

import Foundation
import EosioSwift
import secp256k1
import secp256k1_implementation
import EosioSwiftEcc
import PromiseKit
import EosioSwiftSoftkeySignatureProvider
import EosioSwiftAbieosSerializationProvider


protocol InfraDIDConfApiDependency { // method Construction & Manipulation DID
  
  func setAttributePubKeyDID(action: TransactionAction, key: String,
                             value: String, newKey: String)
}


public class InfraDIDConstructor {
  
  private var idConfig = IdConfiguration() //default Struct
  
  private let defaultPubKeyDidSignDataPrefix = "infra-mainnet"
  
  private var didPubKey: String?
  private var didAccount: String?
  private var did: String = ""
  private var jsonRpc: EosioRpcProvider?
  
  //private var currentCurveType: EllipticCurveType = EllipticCurveType.k1
  
  private var didOwnerPrivateKeyObjc: secp256k1.Signing.PrivateKey?
  private var sigProviderPrivKeys: [String] = []
  
  
  public init(config: IdConfiguration) {
    //first initialized All removed
    idConfig = config
    
    self.idConfig.did = config.did
    
    let didSplit = config.did.split(separator: ":")
    
    guard didSplit.count == 4 else { return }
    //guard currentCurveType == .k1 else { return }
    
    let idNetwork = String(didSplit[3])
    
    if (idNetwork.starts(with: "PUB_K1") || idNetwork.starts(with: "PUB_R1") || idNetwork.starts(with: "EOS")) {
      self.didPubKey = idNetwork
    } else {
      self.didAccount = idNetwork
    }
    
    self.idConfig.registryContract = config.registryContract
    
    let rpc: EosioRpcProvider = EosioRpcProvider(endpoint: URL(string:config.rpcEndpoint)!)
    
    self.jsonRpc = rpc

    let dataPvKey = try! Data(eosioPrivateKey: config.didOwnerPrivateKey)
    let keyPair = try! secp256k1.Signing.PrivateKey.init(rawRepresentation: dataPvKey)
    self.didOwnerPrivateKeyObjc = keyPair
    
    
    sigProviderPrivKeys.append(config.didOwnerPrivateKey)
    if (config.txfeePayerAccount != nil) && (config.txfeePayerPrivateKey != nil) {
      guard let key: String = config.txfeePayerPrivateKey else {return}
      
      sigProviderPrivKeys.append(key)
      idConfig.txfeePayerAccount = config.txfeePayerAccount
    }
    
    idConfig.pubKeyDidSignDataPrefix = config.pubKeyDidSignDataPrefix ?? defaultPubKeyDidSignDataPrefix
    
//    //////////////////////// Setting Finish
//    let pvKeyArray = [UInt8](dataPvKey)
//    let sliceKey = pvKeyArray[1...pvKeyArray.count-1]
    
    
    if idConfig.jwtSigner == nil {
      let signer = JWTSigner.es256(privateKey: dataPvKey)
     // let signature = EcdsaSignature(der: Data(sliceKey), curve: .k1)
      self.idConfig.jwtSigner = signer
    } else {
      self.idConfig.jwtSigner = config.jwtSigner
    }
  }
  
  static public func createPubKeyDID(networkID: String) -> [String: String] {
    
    guard let pvData: Data = generateRandomBytes(bytes: 32) else { return [:] }
    let keyPair = try! secp256k1.Signing.PrivateKey.init(rawRepresentation: pvData)
    
    
    let privateKey: String = keyPair.rawRepresentation.toEosioK1PrivateKey
    let publicKey: String = keyPair.publicKey.rawRepresentation.toEosioK1PublicKey
    let did = "did:infra:\(networkID):\(publicKey)"
    
    return ["did": did, "publicKey": publicKey, "privateKey": privateKey]
  }
}



extension InfraDIDConstructor: InfraDIDConfApiDependency {
  
  private func getNonceForPubKeyDid() -> Promise<Double> {
    
    guard let pubKey: String = self.didPubKey, let jsonRPC = self.jsonRpc else { return Promise<Double>.value(0.0) }
    let dataPubKey = try! Data(eosioPublicKey: pubKey)
    let pubKeyArray = [UInt8](dataPubKey)
    let sliceKey = pubKeyArray[1...pubKeyArray.count-1]
    
    
    let sliceKeyData = Data(sliceKey)
    
    let options: EosioRpcTableRowsRequest = EosioRpcTableRowsRequest(scope: self.idConfig.registryContract, code: self.idConfig.registryContract, table: "pubkeydid", json: true, limit: 1, tableKey: nil, lowerBound: sliceKeyData.hexEncodedString(), upperBound: sliceKeyData.hexEncodedString(), indexPosition: "1", keyType: "sha256", encodeType: .hex, reverse: false, showPayer: false)
    
    var nonce:Double = 0.0
    jsonRPC.getTableRowsPublisher(requestParameters: options)
      .sink { result in
        switch result {
        case .failure(let err):
          iPrint(err.localizedDescription)
        case .finished:
          break
        }
      } receiveValue: { res in
        iPrint(res.rows)
      }
      
    
//    let res = jsonRPC.getTableRows(.promise, requestParameters: options)
//    if res.value == nil {
//      nonce = 0.0
//    }
    
//    return Promise { seal in
//      firstly {
//        jsonRPC.getTableRows(.promise, requestParameters: options)
//      }.done {
//
//        if let row = $0.rows[0] as? [String: Any],
//           let nonceValue = row["nonce"] as? Double
//        {
//          seal.fulfill(nonceValue)
//        } else {
//          seal.fulfill(0.0)
//          print(NSError.init())
//        }
//      }
//    }
    return Promise<Double>.value(nonce)
  }
  
  public func setAttributePubKeyDID(action: TransactionAction, key: String = "",
                             value: String = "", newKey: String = "") {
    let actionName: String = action.rawValue
    var bufArray: [UInt8] = [] //digest buffer initialize
    
    guard let keyPair = self.didOwnerPrivateKeyObjc else { return }
    
    firstly {
      getNonceForPubKeyDid() // Create Nonce
    }
    .done { nonce in
      if let prefixData = self.defaultPubKeyDidSignDataPrefix.data(using: .utf8),
            let actNameData = actionName.data(using: .utf8),
            let pubKeyData = self.didPubKey?.data(using: .utf8),
            let keyData = key.data(using: .utf8),
            let valueData = value.data(using: .utf8),
            let changeKeyData = newKey.data(using: .utf8)
      {
        
        bufArray.append(contentsOf: prefixData)
        bufArray.append(contentsOf: actNameData)
        bufArray.append(contentsOf: keyData)
        bufArray.append(contentsOf: valueData)
        bufArray.append(contentsOf: pubKeyData)
        bufArray.append(UInt8.init(nonce))
        bufArray.append(contentsOf: changeKeyData)
      }

      // bufArray hash And Digest
//      let digest: SHA256Digest = SHA256.hash(data: bufArray)
//      self.idConfig.
//      try! EosioEccSign.signWithK1(publicKey: self.didOwnerPrivateKeyObjc?.publicKey.rawRepresentation, privateKey: self.didOwnerPrivateKeyObjc?.rawRepresentation, data: bufArray)
      
      let signature = try? EosioEccSign.signWithK1(publicKey: keyPair.publicKey.rawRepresentation, privateKey: keyPair.rawRepresentation, data: Data(bufArray))//try! self.didOwnerPrivateKeyObjc?.signature(for: digest)
      
      iPrint(signature)
      
      guard let sign = signature else { return }
      iPrint(sign.toEosioK1Signature)
      let transactionSet: TransactionDefaultSet = TransactionDefaultSet(actionName: action, signKey: sign.toEosioK1Signature)
      
      switch action {
      case .set:
        self.setAttributeTransaction(set: transactionSet, key: key, value: value)
      case .changeOwner:
        self.changeOwnerTransaction(set: transactionSet, newKey: newKey)
      case .revoke:
        self.revokeTransaction(set: transactionSet)
      case .clear:
        self.clearTransaction(set: transactionSet)
      case .setAccount:
        self.setAccountTransaction(set: transactionSet, key: key, value: value)
      }
    }
  }
  
  private func setAttributeTransaction(set: TransactionDefaultSet, key: String, value: String) {
    guard let actor = self.idConfig.txfeePayerAccount, let pubKey = self.didPubKey else { return }
    let action: EosioTransaction.Action = try! EosioTransaction.Action.init(account: EosioName(self.idConfig.registryContract), name: EosioName(set.actionName.rawValue), authorization: [EosioTransaction.Action.Authorization.init(actor: EosioName(actor), permission: EosioName("active"))],
                                                                            data: ["pk": pubKey, "key": key, "value": value, "sig": set.signKey, "ram_payer": actor])

    let transaction = EosioTransaction.init()

    transaction.config.expireSeconds = 30
    transaction.config.blocksBehind = 3
    transaction.rpcProvider = self.jsonRpc
    transaction.signatureProvider = try! EosioSoftkeySignatureProvider(privateKeys: sigProviderPrivKeys)
    transaction.serializationProvider = EosioAbieosSerializationProvider()
    transaction.add(action: action)

    transaction.signAndBroadcast { result in
      switch result {
      case .success(let isSuccess):
        iPrint(isSuccess)
      case .failure(let err):
        iPrint(err.localizedDescription)
      }
    }
  }
  
  private func clearTransaction(set: TransactionDefaultSet) {
    guard let actor = self.idConfig.txfeePayerAccount, let pubKey = self.didPubKey else { return }
    let action: EosioTransaction.Action = try! EosioTransaction.Action.init(account: EosioName(self.idConfig.registryContract), name: EosioName(set.actionName.rawValue), authorization: [EosioTransaction.Action.Authorization.init(actor: EosioName(actor), permission: EosioName("active"))],
        data: ["pk": pubKey, "sig": set.signKey])

    let transaction = EosioTransaction.init()

    transaction.config.expireSeconds = 30
    transaction.config.blocksBehind = 3
    transaction.rpcProvider = self.jsonRpc
    transaction.signatureProvider = try! EosioSoftkeySignatureProvider(privateKeys: sigProviderPrivKeys)
    transaction.serializationProvider = EosioAbieosSerializationProvider()
    transaction.add(action: action)

    transaction.signAndBroadcast { result in
      switch result {
      case .success(let isSuccess):
        iPrint(isSuccess)
      case .failure(let err):
        iPrint(err.localizedDescription)
      }
    }
  }
  
  private func revokeTransaction(set: TransactionDefaultSet) {
    guard let actor = self.idConfig.txfeePayerAccount, let pubKey = self.didPubKey else { return }
    let action: EosioTransaction.Action = try! EosioTransaction.Action.init(account: self.idConfig.registryContract, name: set.actionName.rawValue, authorization: [EosioTransaction.Action.Authorization.init(actor: actor, permission: "active")],
        data: ["pk": pubKey, "sig": set.signKey, "ram_payer": actor])

    let transaction = EosioTransaction.init()

    transaction.config.expireSeconds = 30
    transaction.config.blocksBehind = 3

    transaction.add(action: action)

    transaction.signAndBroadcast { result in
      switch result {
      case .success(let isSuccess):
        iPrint(isSuccess)
      case .failure(let err):
        iPrint(err.localizedDescription)
      }
    }
  }
  
  private func changeOwnerTransaction(set: TransactionDefaultSet, newKey: String) {
    guard let actor = self.idConfig.txfeePayerAccount, let pubKey = self.didPubKey else { return }
    let action: EosioTransaction.Action = try! EosioTransaction.Action.init(account: self.idConfig.registryContract, name: set.actionName.rawValue, authorization: [EosioTransaction.Action.Authorization.init(actor: actor, permission: "active")],
        data: ["pk": pubKey, "new_owner_pk": newKey, "sig": set.signKey, "ram_payer": actor])

    let transaction = EosioTransaction.init()

    transaction.config.expireSeconds = 30
    transaction.config.blocksBehind = 3

    transaction.add(action: action)

    transaction.signAndBroadcast { result in
      switch result {
      case .success(let isSuccess):
        iPrint(isSuccess)
      case .failure(let err):
        iPrint(err.localizedDescription)
      }
    }
  }
  
  private func setAccountTransaction(set: TransactionDefaultSet, key: String, value: String) {
    guard let actor = self.idConfig.txfeePayerAccount, let account = self.didAccount else { return }
    let action: EosioTransaction.Action = try! EosioTransaction.Action.init(account: self.idConfig.registryContract, name: set.actionName.rawValue, authorization: [EosioTransaction.Action.Authorization.init(actor: actor, permission: "active")],
        data: ["account": account, "key": key, "value": value])

    let transaction = EosioTransaction.init()

    transaction.config.expireSeconds = 30
    transaction.config.blocksBehind = 3

    transaction.add(action: action)

    transaction.signAndBroadcast { result in
      switch result {
      case .success(let isSuccess):
        iPrint(isSuccess)
      case .failure(let err):
        iPrint(err.localizedDescription)
      }
    }
  }
  
  public func getJWTIssuer() -> JwtVcIssuer {
    guard let pvKey: Data = try? Data(eosioPrivateKey: self.idConfig.didOwnerPrivateKey) else { return JwtVcIssuer() }
    let signer: JWTSigner = JWTSigner.es256(privateKey: pvKey)
    return JwtVcIssuer(did: self.idConfig.did, alg: "ES256K", signer: signer)
  }
}
