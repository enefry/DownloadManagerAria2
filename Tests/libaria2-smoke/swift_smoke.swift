import Foundation
import libaria2

let version = DMAria2Version()
guard version == "1.37.0" else {
    fatalError("unexpected version: \(version)")
}

_ = DMAria2Session.self

print("DMAria2 Swift smoke ok")
