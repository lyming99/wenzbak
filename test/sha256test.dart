import 'package:wenzbak/src/utils/sha256_util.dart';

void main() async{
  //0326d222589074cca914f7bb59021c545b9a375b24976edc5296ed99e7d22eae
  //
  var sha256 = await Sha256Util.sha256File("C:/Users/98000/Downloads/2026-01-26-05.msg-0 (1).gz");
  print(sha256);
}