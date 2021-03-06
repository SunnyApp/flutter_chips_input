import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chips_input_sunny/flutter_chips_input.dart';
import 'package:logging/logging.dart';
import 'package:logging_config/logging_config.dart';

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
  const MyHomePage({Key key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _textController = TextEditingController();
  final GlobalKey<ChipsInputState<AppProfile>> key = GlobalKey();
  ChipsInputController<AppProfile> controller;
  ChipsInputController<AppProfile> controller2;
  FocusNode focusFirst;

  @override
  void initState() {
    super.initState();
    configureLogging(LogConfig.root(Level.FINE, handler: LoggingHandler.dev()));
    controller = ChipsInputController<AppProfile>(findSuggestions: _findSuggestions);
    controller2 = ChipsInputController<AppProfile>(
      findSuggestions: _findSuggestions,
      hideSuggestionOverlay: true,
    );
    controller.queryStream.after.listen((query) {
      _textController.text = query;
    });
    focusFirst = FocusNode(debugLabel: "first chip focus");
  }

  @override
  void dispose() {
    controller.dispose();
    focusFirst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Flutter Chips Input Example'),
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChipsInput<AppProfile>(
              initialValue: [
                AppProfile(
                    'John Doe', 'jdoe@flutter.io', 'https://d2gg9evh47fn9z.cloudfront.net/800px_COLOURBOX4057996.jpg'),
              ],
              id: "app-profile",
              controller: controller,
              placeholder: "Search contacts",
              autofocus: true,
              enabled: true,
              maxChips: 5,
              chipTokenizer: (profile) => [profile.name, profile.email].where((token) => token != null),
              onSuggestionTap: (chip) {
                controller.addChip(chip, resetQuery: true);
              },
              onInputAction: (_) {
                if (controller.suggestion.isNotEmpty) {
                  controller.addChip(controller.suggestion.item, resetQuery: true);
                }
              },
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
              chipBuilder: (context, _, index, profile) {
                return InputChip(
                  key: ObjectKey(profile),
                  label: Text(profile.name),
                  avatar: CircleAvatar(
                    backgroundImage: NetworkImage(profile.imageUrl),
                  ),
                  onDeleted: () => controller.deleteChip(profile, resetQuery: true),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              },
              suggestionBuilder: (context, _, index, profile) {
                return ListTile(
                  key: ObjectKey(profile),
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(profile.imageUrl),
                  ),
                  title: Text(profile.name),
                  subtitle: Text(profile.email),
                  onTap: () => controller.addChip(profile, resetQuery: true),
                );
              },
            ),
            ChipsInput<AppProfile>(
              initialValue: [
                mockResults[3],
              ],
              id: "app-profile-2",
              controller: controller2,
              placeholder: "Search contacts",
              autofocus: true,
              focusNode: focusFirst,
              enabled: true,
              maxChips: 5,
              chipTokenizer: (profile) => [profile.name, profile.email].where((token) => token != null),
              onSuggestionTap: (chip) {
                controller2.addChip(chip, resetQuery: true);
              },
              onInputAction: (_) {
                if (controller2.suggestion.isNotEmpty) {
                  controller2.addChip(controller2.suggestion.item, resetQuery: true);
                }
              },
              inputConfiguration: TextInputConfiguration(
                autocorrect: false,
              ),
              decoration: InputDecoration(
                // prefixIcon: Icon(Icons.search),
                // hintText: formControl.hint,
                labelText: "No Drop-Down Selector",
                // enabled: false,
                // errorText: field.errorText,
              ),
              chipBuilder: (context, controller, index, profile) {
                return InputChip(
                  key: ObjectKey(profile),
                  label: Text(profile.name),
                  avatar: CircleAvatar(
                    backgroundImage: NetworkImage(profile.imageUrl),
                  ),
                  onDeleted: () => controller.deleteChip(profile, resetQuery: true),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              },
              suggestionBuilder: (context, _, index, profile) {
                return ListTile(
                  key: ObjectKey(profile),
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(profile.imageUrl),
                  ),
                  title: Text(profile.name),
                  subtitle: Text(profile.email),
                  onTap: () => controller2.addChip(profile, resetQuery: true),
                );
              },
            ),
            Wrap(
              spacing: 5,
              children: [
                MaterialButton(
                  elevation: 1,
                  color: Colors.orange,
                  onPressed: () {
                    controller.setQuery("", isInput: false);
                  },
                  child: Text("Reset Search"),
                ),
                MaterialButton(
                  elevation: 1,
                  color: Colors.orange,
                  onPressed: () {
                    controller2.setInlineSuggestion(mockResults[4], notify: true);
                  },
                  child: Text("Set Suggestion"),
                ),
                MaterialButton(
                  elevation: 1,
                  color: Colors.green,
                  onPressed: () {
                    controller.syncChips([
                      mockResults[3],
                      mockResults[7],
                    ], source: ChipChangeOperation.external);
                  },
                  child: Text("Set Chips"),
                ),
                MaterialButton(
                  elevation: 1,
                  color: Colors.green,
                  onPressed: () {
                    controller.syncChips([
                      mockResults[3],
                      mockResults[7],
                      mockResults[6],
                      mockResults[2],
                      mockResults[7],
                    ], source: ChipChangeOperation.external);
                  },
                  child: Text("Set Chips Long"),
                )
              ],
            ),
          ],
        ),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  ChipSuggestions<AppProfile> _findSuggestions(String query) {
    if (query.isNotEmpty) {
      var lowercaseQuery = query.toLowerCase();
      var foundResults = mockResults.where(
        (profile) {
          return profile.name.toLowerCase().contains(lowercaseQuery) ||
              profile.email.toLowerCase().contains(lowercaseQuery);
        },
      ).toList(growable: false)
        ..sort((a, b) =>
            a.name.toLowerCase().indexOf(lowercaseQuery).compareTo(b.name.toLowerCase().indexOf(lowercaseQuery)));
      var exactMatch = mockResults.firstWhere(
        (profile) => profile.name.toLowerCase() == lowercaseQuery || profile.email.toLowerCase() == lowercaseQuery,
        orElse: () => null,
      );
      return ChipSuggestions<AppProfile>(
          suggestions: foundResults,
          match: foundResults.length == 1 && exactMatch != null
              ? Suggestion.highlighted(item: exactMatch, highlightText: exactMatch.name)
              : Suggestion.empty());
    } else {
      return const ChipSuggestions.empty();
    }
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
