import SlidePilotCore

extension RemoteCurtain {
    /// The curtain the presentation shows (CUR-01), for the controller (REM-04).
    public init(_ curtain: Curtain) {
        self = switch curtain {
        case .none: .none
        case .black: .black
        case .white: .white
        }
    }
}

extension Curtain {
    /// The curtain a controller asks for (REM-05).
    public init(_ curtain: RemoteCurtain) {
        self = switch curtain {
        case .none: .none
        case .black: .black
        case .white: .white
        }
    }
}
