class IndexUtil {
  IndexUtil._();

  static Map<String, String> readIndexMap(String indexContent) {
    var indexesMap = <String, String>{};
    var lines = indexContent.split("\n");
    for (var line in lines) {
      var pos = line.indexOf(" ");
      if (pos != -1) {
        var sha256 = line.substring(0, pos);
        var filepath = line.substring(pos + 1);
        indexesMap[filepath] = sha256;
      }
    }
    return indexesMap;
  }
}
