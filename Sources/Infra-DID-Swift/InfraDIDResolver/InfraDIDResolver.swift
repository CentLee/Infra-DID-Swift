//
//  File.swift
//  
//
//  Created by SatGatLee on 2021/11/23.
//

import Foundation
import PromiseKit
import EosioSwift
import secp256k1



public enum verificationMethodTypes: String {
  case EcdsaSecp256k1VerificationKey2019 = "EcdsaSecp256k1VerificationKey2019"
  case EcdsaSecp256k1RecoveryMethod2020 = "EcdsaSecp256k1RecoveryMethod2020"
  case Ed25519VerificationKey2018 = "Ed25519VerificationKey2018"
  case RSAVerificationKey2018 = "RSAVerificationKey2018"
  case X25519KeyAgreementKey2019 = "X25519KeyAgreementKey2019"
}

public struct ResolvedDIDDocument {
  var didDocument: DIDDocument?
  var deactivated: Bool
  
  public init(didDocument: DIDDocument? = nil, deactivated: Bool = false) {
    self.didDocument = didDocument
    self.deactivated = deactivated
  }
}

public protocol InfraDIDResolvable {
  func resolve(did: String, parsed: ParsedDID, unUsed: Resolver, options: DIDResolutionOptions) -> Promise<DIDResolutionResult>
}


public func getResolver(options: ConfigurationOptions) -> [String:DIDResolverType] {
  return InfraDIDResolver(options: options).build()
}

public class InfraDIDResolver {
  private var networks: ConfiguredNetworks
  private var noRevocationCheck: Bool
  
  public init(options: ConfigurationOptions) {
    self.networks = configureResolverWithNetworks(conf: options)
    
    if options.noRevocationCheck {
      self.noRevocationCheck = true
    } else {
      self.noRevocationCheck = false
    }
  }
}

extension InfraDIDResolver: InfraDIDResolvable {
  public func resolve(did: String, parsed: ParsedDID, unUsed: Resolver, options: DIDResolutionOptions) -> Promise<DIDResolutionResult> {
    
    let idSplit = parsed.id.split(separator: ":")
    
    if (idSplit.count != 2) {
      return Promise<DIDResolutionResult>.value(DIDResolutionResult(
        didResolutionMetadata: DIDResolutionMetadata(contentType: nil, errorDescription: .invalidDid,
                                                     message: "invalid did, needs network identifier part and id part (\(did))"),
        didDocument: nil,
        didDocumentMetaData: DIDDocumentMetaData()))
    }
    
    guard let network: ConfiguredNetwork = self.networks[String(idSplit[0])] else { return emptyResult }
    if network.jsonRPC == nil {
      return Promise<DIDResolutionResult>.value(DIDResolutionResult(didResolutionMetadata: DIDResolutionMetadata(contentType: nil, errorDescription: .unKnownNetwork, message: "no chain network configured for network identifier \(idSplit[0])"), didDocument: nil, didDocumentMetaData: DIDDocumentMetaData()))
    }
    
    do {
      let idInNetwork: String = String(idSplit[1])
      var resolvedDIDDoc = ResolvedDIDDocument(didDocument: DIDDocument(), deactivated: true)
      
      if idInNetwork.starts(with: "PUB_K1") || idInNetwork.starts(with: "PUB_R1") || idInNetwork.starts(with: "EOS") {
        guard let value = self.resolvePubKeyDID(did: did, pubKey: idInNetwork, network: network).value else { return emptyResult }
        resolvedDIDDoc = value
      } else {
        guard let value = self.resolveAccountDID(did: did, accountName: idInNetwork, network: network).value else { return emptyResult }
        resolvedDIDDoc = value
      }
      
      let status = resolvedDIDDoc.deactivated
      guard let document = resolvedDIDDoc.didDocument else { return Promise<DIDResolutionResult>.value(DIDResolutionResult())}
      
      return Promise<DIDResolutionResult>.value(DIDResolutionResult(didResolutionMetadata: DIDResolutionMetadata(contentType: "application/did+ld+json", errorDescription: nil, message: nil)
                                                                    , didDocument: document
                                                                    , didDocumentMetaData: DIDDocumentMetaData(created: nil, updated: nil, deactivated: status, versionId: nil, nextUpdate: nil, nextVersionId: nil, equivalentId: nil, canonicalId: nil)))
      
    }
//    catch(let err) {
//      return Promise<DIDResolutionResult>.value(DIDResolutionResult(didResolutionMetadata: DIDResolutionMetadata(contentType: nil, errorDescription: .notFound, message: err.localizedDescription), didDocument: nil, didDocumentMetaData: DIDDocumentMetaData()))
//    }
  } //resolve
  
  public func build() -> [String:DIDResolverType] {
    //self.resolve().bind(self)
    return ["infra": self.resolve]
  }
  
  
  private func resolvePubKeyDID(did: String, pubKey: String, network: ConfiguredNetwork) -> Promise<ResolvedDIDDocument> {
    let pubKeyData = try! Data(eosioPublicKey: pubKey)
    let pubKeyArray = [UInt8](pubKeyData)
    let sliceKey = pubKeyArray[1...pubKeyArray.count-1]
    
    
    let sliceKeyData = Data(sliceKey)
    let pubKeyIndex = sliceKeyData.hexEncodedString()
    guard let jsonRpc = network.jsonRPC else { return Promise<ResolvedDIDDocument>.value(ResolvedDIDDocument()) }
    
    //initialized
    //Todo Promise Chain Creation
//
//    let resPubKeyDID = jsonRpcFetchRows(rpc: jsonRpc, options: EosioRpcTableRowsRequest(scope: network.regisrtyContract, code: network.regisrtyContract, table: "pubkeydid", json: true, limit: 1, tableKey: nil, lowerBound: pubKeyIndex, upperBound: pubKeyIndex, indexPosition: "2", keyType: "sha256", encodeType: .hex, reverse: nil, showPayer: nil))
    
   // var pkDidAttr = [[:]]
    var deactivated: Bool = false
//    guard let value = resPubKeyDID.value, let didAttr = value as? [String:Any] else { return emptyResolvedDocument }
    //pkDidAttr = resPubKeyDID["attr"]
//
//    if self.noRevocationCheck == false && didAttr["nonce"] as? Double == 65535 {
//      deactivated = true
//    }
    
//    let resPubKeyDIDOwner = jsonRpcFetchRows(rpc: jsonRpc, options: EosioRpcTableRowsRequest(scope: network.regisrtyContract, code: network.regisrtyContract, table: "pkdidowner", json: true, limit: 1, tableKey: nil, lowerBound: didAttr["pkid"] as? String , upperBound: nil, indexPosition: "1", keyType: "i64", encodeType: .hex, reverse: nil, showPayer: nil))
    
//    guard let value = resPubKeyDIDOwner.value, let didAttr = value as? [String:Any] else { return emptyResolvedDocument }
//    let pubKey = try! Data(eosioPublicKey: didAttr["pk"] as! String )
//
    return Promise { seal in
      firstly {
        jsonRpcFetchRows(rpc: jsonRpc, options: EosioRpcTableRowsRequest(scope: network.regisrtyContract, code: network.regisrtyContract, table: "pubkeydid", json: true, limit: 1, tableKey: nil, lowerBound: pubKeyIndex, upperBound: pubKeyIndex, indexPosition: "2", keyType: "sha256", encodeType: .hex, reverse: nil, showPayer: nil))
      }.then({ attr -> Promise<[String:Any]> in
        var deactivated: Bool = false
        //guard let didAttr = $0 else { return emptyResolvedDocument }
        
        if self.noRevocationCheck == false && attr["nonce"] as? Double == 65535 {
          deactivated = true
        }
        return self.jsonRpcFetchRows(rpc: jsonRpc, options: EosioRpcTableRowsRequest(scope: network.regisrtyContract, code: network.regisrtyContract, table: "pkdidowner", json: true, limit: 1, tableKey: nil, lowerBound: attr["pkid"] as? String , upperBound: nil, indexPosition: "1", keyType: "i64", encodeType: .hex, reverse: nil, showPayer: nil))
      }).done({ attr in
        let pubKey = try! Data(eosioPublicKey: attr["pk"] as! String )
        seal.fulfill(self.wrapDidDocument(did: did, controllerPubKey: pubKey, pkdidAttr: attr, deactivated: deactivated))
      }).catch {
        iPrint($0.localizedDescription)
      }
    }
    
    
//
//
//    return Promise { seal in
//      firstly {
//        self.wrapDidDocument(did: did, controllerPubKey: pubKey, pkdidAttr: didAttr, deactivated: deactivated)
//      }.done { document in
//        seal.fulfill(document)
//      }
//    }
  }
  
  private func resolveAccountDID(did: String, accountName: String, network: ConfiguredNetwork) -> Promise<ResolvedDIDDocument> {
    var activeKeyStr = ""
    guard let rpc = network.jsonRPC else { return emptyResolvedDocument }
    //let res = rpc.getAccount(.promise, requestParameters: EosioRpcAccountRequest(accountName: accountName))
//    guard let resValue = res.value else { return emptyResolvedDocument }
//
//    let eosioRpcAccountResponse = resValue
//    let permissions = eosioRpcAccountResponse.permissions
//    guard let activePermission = permissions.filter({$0.permName == "active"}).first,
//          let keysAndWeight = activePermission.requiredAuth.keys.first  else { return emptyResolvedDocument }
//    activeKeyStr = keysAndWeight.key
//    let pubKey = try! Data(eosioPublicKey: activeKeyStr)
//
//    let resRows = self.jsonRpcFetchRows(rpc: rpc, options: EosioRpcTableRowsRequest(scope: network.regisrtyContract, code: network.regisrtyContract, table: "accdidattr", json: true, limit: 1, tableKey: nil, lowerBound: accountName, upperBound: accountName, indexPosition: "1", keyType: "name", encodeType: .hex, reverse: nil, showPayer: nil))
    
    return Promise { seal in
      firstly {
        rpc.getAccount(.promise, requestParameters: EosioRpcAccountRequest(accountName: accountName))
      }.then({ resValue -> Promise<[String:Any]> in
        let eosioRpcAccountResponse = resValue
        let permissions = eosioRpcAccountResponse.permissions
        guard let activePermission = permissions.filter({$0.permName == "active"}).first,
              let keysAndWeight = activePermission.requiredAuth.keys.first  else { return Promise<[String:Any]>.value([:]) }
        activeKeyStr = keysAndWeight.key
        
        return self.jsonRpcFetchRows(rpc: rpc, options: EosioRpcTableRowsRequest(scope: network.regisrtyContract, code: network.regisrtyContract, table: "accdidattr", json: true, limit: 1, tableKey: nil, lowerBound: accountName, upperBound: accountName, indexPosition: "1", keyType: "name", encodeType: .hex, reverse: nil, showPayer: nil))
      })
      .done { attr in
        let pubKey = try! Data(eosioPublicKey: activeKeyStr)
        seal.fulfill(self.wrapDidDocument(did: did, controllerPubKey: pubKey, pkdidAttr: attr, deactivated: false))
      }
      .catch {
        iPrint($0.localizedDescription)
      }
    }
    
    
  }
  
  private func jsonRpcFetchRows(rpc: EosioRpcProvider, options: EosioRpcTableRowsRequest) -> Promise<[String:Any]> {
    var mergedOptions = options
    mergedOptions.limit = 9999
    
    return Promise { seal in
      firstly {
        rpc.getTableRows(.promise, requestParameters: mergedOptions)
      }.done {
        if let row = $0.rows[0] as? [String:Any] {
          seal.fulfill(row)
        }
      }
    }
  }
  
  private func wrapDidDocument(did: String, controllerPubKey: Data?, pkdidAttr: [String:Any], deactivated: Bool) -> ResolvedDIDDocument {
    guard let pubKey = controllerPubKey?.hexEncodedString() else { return ResolvedDIDDocument() }
    var baseDidDocument = DIDDocument(context: contextType.string("https://www.w3.org/ns/did/v1"), id: did, alsoKnownAs: nil, controller: nil, verificationMethod: [], service: nil, publicKey: nil, authentication: [])
    let publicKeys = [VerificationMethod(id: "\(did)#controller", type: verificationMethodTypes.EcdsaSecp256k1VerificationKey2019.rawValue, controller: did, publicKeyBase58: nil, publicKeyBase64: nil, publicKeyJwk: nil, publicKeyHex: pubKey, publicKeyMultibase: nil, blockchainAccountId: nil, ethereumAddress: nil)]
    
    let authentication = ["\(did)#controller"]
    var serviceEndpoints: [ServiceEndpoint] = []
    
    var serviceCount = 0
    guard let attr = pkdidAttr["attr"] as? [String:String] else { return ResolvedDIDDocument() }
    for (key, value) in attr {
      let split = key.split(separator: "/")
      if split.count > 0 {
        let attrType = split[0]
        switch attrType {
        case "svc":
          serviceCount += 1
          serviceEndpoints.append(ServiceEndpoint(id: "\(did)#service-\(serviceCount)",
                                                              type: split.count > 1 ? String(split[1]) : "AgentService"
                                                              , serviceEndpoint: value, description: nil))
          break
        default:
          break
        }
      }
    }

    baseDidDocument.verificationMethod = publicKeys
    baseDidDocument.authentication = authentication
    
    if serviceEndpoints.count > 0 {
      baseDidDocument.service = serviceEndpoints
    }
    return ResolvedDIDDocument(didDocument: baseDidDocument, deactivated: deactivated)
  }
  
  
} //class indent

//                                          rows: [
//                                            {
//                                              pkid: 3,
//                                              pk: 'EOS5TaEgpVur391dimVnFCDHB122DXYBbwWdKUpEJCNv3knyTzRMd',
//                                              nonce: 3,
//                                              attr: []
//                                            }
//                                          ],
