/// Titles the app picker with what the user has chosen so far.
///
/// The picker's own list is the only feedback iOS gives while it is open, so the
/// title carries the running count. Only individual apps count: a category or
/// website tap leaves the number where it was, which is what tells the user it
/// did not take.
public enum PickerTitle {
    public static func text(forSelectedAppCount count: Int) -> String {
        switch count {
        case 1:
            return "1 app selected"
        case 2...:
            return "\(count) apps selected"
        default:
            return "Choose apps"
        }
    }
}
