import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chips_input_sunny/flutter_chips_input.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Chips Input',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _textController = TextEditingController();
  final GlobalKey<ChipsInputState<AppProfile>> key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _textController.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    const mockResults = <AppProfile>[
      AppProfile('John Doe', 'jdoe@flutter.io', 'https://d2gg9evh47fn9z.cloudfront.net/800px_COLOURBOX4057996.jpg'),
      AppProfile('Paul', 'paul@google.com', 'https://mbtskoudsalg.com/images/person-stock-image-png.png'),
      AppProfile('Fred', 'fred@google.com',
          'https://media.istockphoto.com/photos/feeling-great-about-my-corporate-choices-picture-id507296326'),
      AppProfile('Brian', 'brian@flutter.io',
          'https://upload.wikimedia.org/wikipedia/commons/7/7c/Profile_avatar_placeholder_large.png'),
      AppProfile('John', 'john@flutter.io',
          'https://upload.wikimedia.org/wikipedia/commons/7/7c/Profile_avatar_placeholder_large.png'),
      AppProfile('Thomas', 'thomas@flutter.io',
          'https://upload.wikimedia.org/wikipedia/commons/7/7c/Profile_avatar_placeholder_large.png'),
      AppProfile('Nelly', 'nelly@flutter.io',
          'https://upload.wikimedia.org/wikipedia/commons/7/7c/Profile_avatar_placeholder_large.png'),
      AppProfile('Marie', 'marie@flutter.io',
          'https://upload.wikimedia.org/wikipedia/commons/7/7c/Profile_avatar_placeholder_large.png'),
      AppProfile('Charlie', 'charlie@flutter.io',
          'https://upload.wikimedia.org/wikipedia/commons/7/7c/Profile_avatar_placeholder_large.png'),
      AppProfile('Diana', 'diana@flutter.io',
          'https://upload.wikimedia.org/wikipedia/commons/7/7c/Profile_avatar_placeholder_large.png'),
      AppProfile('Ernie', 'ernie@flutter.io',
          'https://upload.wikimedia.org/wikipedia/commons/7/7c/Profile_avatar_placeholder_large.png'),
      AppProfile('Gina', 'fred@flutter.io',
          'https://upload.wikimedia.org/wikipedia/commons/7/7c/Profile_avatar_placeholder_large.png'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Flutter Chips Input Example'),
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ChipsInput<AppProfile>(
              initialValue: [
                AppProfile(
                    'John Doe', 'jdoe@flutter.io', 'https://d2gg9evh47fn9z.cloudfront.net/800px_COLOURBOX4057996.jpg'),
              ],
              key: key,
              autofocus: true,
              enabled: true,
              maxChips: 5,
              onQueryChanged: (query) => _textController.text = query,
              inputConfiguration: TextInputConfiguration(
                autocorrect: false,
              ),
              decoration: InputDecoration(
                // prefixIcon: Icon(Icons.search),
                // hintText: formControl.hint,
                labelText: "Select People",
                // enabled: false,
                // errorText: field.errorText,
              ),
              findSuggestions: (String query) {
                if (query.length != 0) {
                  var lowercaseQuery = query.toLowerCase();
                  var foundResults = mockResults.where(
                    (profile) {
                      return profile.name.toLowerCase().contains(lowercaseQuery) ||
                          profile.email.toLowerCase().contains(lowercaseQuery);
                    },
                  ).toList(growable: false)
                    ..sort((a, b) => a.name
                        .toLowerCase()
                        .indexOf(lowercaseQuery)
                        .compareTo(b.name.toLowerCase().indexOf(lowercaseQuery)));
                  var exactMatch = mockResults.firstWhere(
                    (profile) =>
                        profile.name.toLowerCase() == lowercaseQuery || profile.email.toLowerCase() == lowercaseQuery,
                    orElse: () => null,
                  );
                  return ChipSuggestions(
                      suggestions: foundResults,
                      match: foundResults.length == 1 && exactMatch != null ? exactMatch : null);
                } else {
                  return ChipSuggestions.empty;
                }
              },
              onChanged: (data) {
                print(data);
              },
              chipBuilder: (context, state, profile) {
                return InputChip(
                  key: ObjectKey(profile),
                  label: Text(profile.name),
                  avatar: CircleAvatar(
                    backgroundImage: NetworkImage(profile.imageUrl),
                  ),
                  onDeleted: () => state.deleteChip(profile),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              },
              suggestionBuilder: (context, state, profile) {
                return ListTile(
                  key: ObjectKey(profile),
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(profile.imageUrl),
                  ),
                  title: Text(profile.name),
                  subtitle: Text(profile.email),
                  onTap: () => state.selectSuggestion(profile),
                );
              },
            ),
            TextField(
              enabled: false,
              controller: _textController,
            ),
            MaterialButton(
              elevation: 1,
              color: Colors.orange,
              onPressed: () {
                key.currentState.query = "";
              },
              child: Text("Reset Search"),
            ),
            MaterialButton(
              elevation: 1,
              color: Colors.blue,
              onPressed: () {
                key.currentState.query = "Bill";
              },
              child: Text("Set Query"),
            ),
            MaterialButton(
              elevation: 1,
              color: Colors.green,
              onPressed: () {
                key.currentState.syncChips([
                  mockResults[3],
                  mockResults[7],
                ]);
              },
              child: Text("Set Chips"),
            ),
          ],
        ),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

class AppProfile {
  final String name;
  final String email;
  final String imageUrl;

  const AppProfile(this.name, this.email, this.imageUrl);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AppProfile && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return name;
  }
}
