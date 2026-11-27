(:background)
const InCmd_subjectsChanged = "s";
(:background)
const InCmd_acceptQueryResult = "a";
(:background)
const InCmd_openAppFailed = "f";
(:background)
const InCmd_openMeCompleted = "c";

(:background)
const OpenMeCompletedArgs_succeeded = "e";
(:background)
const OpenMeCompletedArgs_messageForWakingUp = "m";

(:background)
const InCmd_searchResults = "r";

const SearchResultsArgs_query = "q";
const SearchResultsArgs_list = "l";
const SearchResultsArgs_error = "e";

// Result of sending a text message, reported by the phone for SmsArgsK_requestId.
(:background)
const InCmd_smsResult = "m";

const SmsResultArgs_requestId = "i";
// Absent when the message was sent; otherwise one of the SmsError_* codes.
const SmsResultArgs_error = "e";
