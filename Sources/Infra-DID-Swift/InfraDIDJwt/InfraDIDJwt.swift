//
//  File.swift
//
//
//  Created by SatGatLee on 2021/11/25.
//

import Foundation
import PromiseKit
import EosioSwiftEcc


public let selfIssuedV2 = "https://self-issued.me/v2"
public let selfIssuedV1 = "https://self-issued.me"
fileprivate let defaultAlg = "ES256K"
fileprivate let didJson = "application/did+json"
public let nbfSkew: Double = 300


private func decodeJws(jws: String) -> JwsDecoded {
  let pattern = "([a-zA-Z0-9_-]+)"
  let part = jws.matchingStrings(regex: "^\(pattern).\(pattern).\(pattern)$")[0]
  
  var decodeJws = JwsDecoded()
  
  if !part.isEmpty {
    decodeJws = JwsDecoded(header: Header(), payload: part[2], signature: part[3], data: "\(part[1])\(part[2])")
  }
  
  return decodeJws
}

public func decodeJwt(jwt: String) -> JwtDecoded { //jwt값을 decode하고 그 안의 payload를 디코딩해서 json 형태로 파싱하고 객체에 복사한다.
  if jwt == "" { NSError.init().localizedDescription }
  
  var decodeJwt = JwtDecoded()
  
  do {
    let jws = decodeJws(jws: jwt)
    
    let jsonEncoder = JSONEncoder()
    jsonEncoder.dataEncodingStrategy = .base64
    let baseData = base64urlDecodedData(base64urlEncoded: jws.payload)
    let jsonDecoder = JSONDecoder()
    jsonDecoder.dateDecodingStrategy = .secondsSince1970
    let data = try jsonDecoder.decode(JwtPayload.self, from: baseData ?? Data.init())
    decodeJwt = JwtDecoded(header: jws.header, payload: data, signature: jws.signature, data: jws.data)
  } catch (let err) {
    iPrint(err.localizedDescription)
  }
  return decodeJwt
}

public enum PayloadType {
  case string(String)
  case jwtPayload(JwtPayload?)
}

private func createJws(payload: JwtPayload, signer: JWTSigner, header: Header?, options: JwsCreationOptions) async -> String {
  guard let header = header else { return ""}
  
  var jwt = JWT(header: header, claims: payload)
  guard let signedJwt: String = try? await jwt.sign(using: signer) else { return "" }
  return signedJwt
}


public func createJwt(payload: JwtPayload, jwtOptions: JwtOptions, header: Header) async throws -> String {
  var fullPayload: JwtPayload = payload
  fullPayload.iat = Date.now
  
  if jwtOptions.expiresIn != nil {
    
    let timestamps: Date  = (payload.nbf != nil) ? payload.nbf! : Date.now
    
    fullPayload.exp = Date(timeIntervalSince1970: (floor(Double(timestamps.timeIntervalSinceNow) / 1000) + floor(jwtOptions.expiresIn!)))
  }
  
  guard let signer = jwtOptions.signer else { return ""}
  fullPayload.iss = jwtOptions.issuer
  
  var header = header
  
  if header.alg == "" { header.alg = defaultAlg }
  return await createJws(payload: fullPayload, signer: signer, header: header, options: JwsCreationOptions(canonicalize: jwtOptions.canonicalize))
}

public func verifyJwt(jwt: String, options: JwtVerifyOptions) async throws -> JwtVerified {
  let jwtDecoded = decodeJwt(jwt: jwt)
  
  var proofPurpose: ProofPurposeTypes? = options.proofPurpose ?? nil
  var resultVerified = JwtVerified()

  guard let resolver = options.resolver else { throw JWTError(localizedDescription: "resolver error") }
  
  if options.auth != nil {
    proofPurpose = options.auth! ? ProofPurposeTypes.authentication : options.proofPurpose
  }
  
  if jwtDecoded.payload.iss == nil {
    throw JWTError(localizedDescription: "invalid_jwt: JWT iss is required")
  }
  
  var did = ""
  
  if jwtDecoded.payload.iss == selfIssuedV2 {
    if jwtDecoded.payload.sub == nil {
      throw JWTError(localizedDescription: "invalid_jwt: JWT sub is required")
    }
  
    did = jwtDecoded.payload.sub != nil ? jwtDecoded.payload.sub ?? "" : String((jwtDecoded.header.kid?.split(separator: "#")[0])!)
  }
  else if jwtDecoded.payload.iss == selfIssuedV1 {
    if jwtDecoded.payload.did == nil {
      throw JWTError(localizedDescription: "invalid_jwt: JWT did is required")
    }
    did = jwtDecoded.payload.did ?? ""
  } else {
    did = jwtDecoded.payload.iss ?? ""
  }
  
  if did == "" {
    throw JWTError(localizedDescription: "invalid_jwt: No DID has been found in the JWT")
  }
  
  guard let authenticator = try? await resolveAuthenticator(resolver: resolver, alg: jwtDecoded.header.alg!, issuer: did, proofPurpose: proofPurpose ?? .authentication) else { return JwtVerified() }
  iPrint(authenticator)

  guard let verified = try? await resolveVerified(authenticator: authenticator, jwt: jwt, jwtDecoded: jwtDecoded, options: options) else { return JwtVerified() }
  
  return verified

}

private func resolveVerified(authenticator: DIDAuthenticator, jwt: String, jwtDecoded: JwtDecoded, options: JwtVerifyOptions) async throws -> JwtVerified {
  iPrint(jwtDecoded.payload)
  if authenticator.authenticators.count > 1 {
    iPrint(authenticator.authenticators)
  } else if authenticator.authenticators.count != 0 {
    guard let keyHex = authenticator.authenticators[0].publicKeyHex, let pubKey = try? Data(hex: keyHex) else { throw JWTError(localizedDescription: "not Found Key") }

    iPrint(pubKey.toEosioK1PublicKey)
    let verifier = JWTVerifier.es256(publicKey: pubKey)
    iPrint(authenticator.issuer)
    let isVerified = verifier.verify(jwt: jwt)
    
    guard isVerified else { throw JWTError(localizedDescription: "not Verified Jwt")}
  }
  
  let auth = authenticator.authenticators[0]
  
  let now = floor(Double(Date.now.timeIntervalSinceNow) / 1000)
  let skewTimes = options.skewTime != nil && options.skewTime! > 0 ? options.skewTime! : nbfSkew
  if auth.id != "" {
    let nowSkewed = now + skewTimes
    //1
    if jwtDecoded.payload.nbf != nil {
      guard let nbf = jwtDecoded.payload.nbf else { throw JWTError(localizedDescription: "Nil Error")}
      iPrint(floor(Double(nbf.timeIntervalSinceNow) / 1000))
      if floor(Double(nbf.timeIntervalSinceNow) / 1000) > nowSkewed {
        throw JWTError(localizedDescription: "invalid_jwt: JWT not valid before nbf: \(nbf)")
      }
    }
    //2
    else if jwtDecoded.payload.iat != nil {
      guard let iat = jwtDecoded.payload.iat else { throw JWTError(localizedDescription: "Nil Error")}
      if floor(Double(iat.timeIntervalSinceNow) / 1000) > nowSkewed {
        throw JWTError(localizedDescription: "invalid_jwt: JWT not valid before iat: \(iat)")
      }
    }
    
    
    if jwtDecoded.payload.exp != nil {
      guard let exp = jwtDecoded.payload.exp else { throw JWTError(localizedDescription: "Nil Error")}
      let expDouble = floor((Double(exp.timeIntervalSinceNow) / 1000))
      if expDouble <= now - skewTimes {
        throw JWTError(localizedDescription: "invalid_jwt: JWT not valid before exp: \(exp)")
      }
    }
    
    if jwtDecoded.payload.aud != nil {
      guard let aud = jwtDecoded.payload.aud else { throw JWTError(localizedDescription: "Nil Error")}
      
      if options.audience == nil && options.callbackUrl == nil {
        throw JWTError(localizedDescription: "invalid_config: JWT audience is required but your app address has not been configured")
      }
    }
  }
  return JwtVerified(didResolutionResult: authenticator.didResolutionResult, issuer: authenticator.issuer, signer: auth, jwt: jwt, payload: jwtDecoded.payload)
}


private func resolveAuthenticator(resolver: Resolvable, alg: String, issuer: String, proofPurpose: ProofPurposeTypes) async throws -> DIDAuthenticator {
  let verifyType = alg != "" ? "EcdsaSecp256k1VerificationKey2019" : ""
  
  guard verifyType != "" else { throw JWTError(localizedDescription: "not_supported: No supported signature types for algorithm")}
  
  var didResult = DIDResolutionResult()
  var authenticator = DIDAuthenticator()
  
  let res = await resolver.resolve(didUrl: issuer, options: DIDResolutionOptions(accept: didJson))
  
  if res.isFulfilled && res.value != nil {
    guard let result = res.value else { return DIDAuthenticator() }
    if result.didDocument == nil {
      didResult.didDocument = result.didDocument
    } else {
      didResult = result
    }
    
    if didResult.didResolutionMetadata.errorDescription != nil || didResult.didDocument == nil {
      throw JWTError(localizedDescription: "resolver_error: Unable to resolve DID document for \(issuer)")
    }
    
    var publicKeysCheck: [VerificationMethod] = didResult.didDocument?.verificationMethod?.count != 0 ? (didResult.didDocument?.verificationMethod)! : (didResult.didDocument?.publicKey)!
    
    if proofPurpose == .assertionMethod && didResult.didDocument?.assertionMethod.count == 0{
      didResult.didDocument?.assertionMethod = publicKeysCheck.map {$0.id}
    }
    
    
    publicKeysCheck.map { verify -> VerificationMethod in
      var method: VerificationMethod? = nil
      switch proofPurpose {
      case .assertionMethod:
        method = getPublicKeyById(verificationsMethods: publicKeysCheck, pubid: didResult.didDocument?.assertionMethod.first ?? nil)
      case .capabilityDelegation:
        method = getPublicKeyById(verificationsMethods: publicKeysCheck, pubid: didResult.didDocument?.capabilityDelegation.first ?? nil)
      case .capabilityInvocation:
        method = getPublicKeyById(verificationsMethods: publicKeysCheck, pubid: didResult.didDocument?.capabilityInvocation.first ?? nil)
      case .authentication:
        method = getPublicKeyById(verificationsMethods: publicKeysCheck, pubid: didResult.didDocument?.authentication.first ?? nil)
      }
      return method!
    }
    
    publicKeysCheck = publicKeysCheck.filter { $0.id != "" }
    
    let authenticators: [VerificationMethod] = publicKeysCheck.filter { $0.type == "EcdsaSecp256k1VerificationKey2019" }
    
    if authenticators.count == 0 {
      throw JWTError(localizedDescription: "no_suitable_keys: DID document for \(issuer) does not have public keys suitable for \(alg) with \(proofPurpose.rawValue) purpose")
    }
    
    authenticator =  DIDAuthenticator(authenticators: authenticators, issuer: issuer, didResolutionResult: didResult)

  }
  return authenticator
}

public func getPublicKeyById(verificationsMethods: [VerificationMethod], pubid: String? = nil) -> VerificationMethod? {
  let filtered = verificationsMethods.filter {$0.id == pubid}
  return filtered.count > 0 ? filtered[0] : nil
}