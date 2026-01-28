void main()async{
  var time = DateTime.now().millisecondsSinceEpoch;
  try {
    await Future.wait([
        test(100),
        test(200),
        test(300),
        test(400),
        test(500),
        test(600),
        test(700),
        test(800),
      ]);
  } catch (e) {
    print(e);
  }
  print(DateTime.now().millisecondsSinceEpoch - time);
}
Future test(int delay)async{
  print(delay);
  await Future.delayed(Duration(milliseconds: delay));
  throw "interrupted";
}