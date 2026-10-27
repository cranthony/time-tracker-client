// Circles and communities: a plain circle named on an event or goal
// stands for its members but those its except leaves out; a community
// stands for itself. Read and sent as the server has them, picked, named
// and scored.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/attendance.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/facts.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/recurring_goal.dart';
import 'package:time_tracker_client/models/scoring.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/models/trait_scores.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/goal_drafts.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/widgets/goal_editor.dart';
import 'package:time_tracker_client/widgets/person_dialog.dart';
import 'package:time_tracker_client/widgets/picker_sheet.dart';

const _self = Person(id: selfPersonId, name: 'Self', circleIds: ['fam']);
const _sam = Person(id: 'sam', name: 'Sam', circleIds: ['fam']);
const _uly = Person(id: 'uly', name: 'Ulyssie', circleIds: ['fam']);
const _jo = Person(id: 'jo', name: 'Jo', circleIds: ['club']);

/// Family, a plain circle; the club, a community.
const _family = Circle(
  id: 'fam',
  name: 'Family',
  memberIds: [selfPersonId, 'sam', 'uly'],
);
const _club = Circle(
  id: 'club',
  name: 'Club',
  kind: CircleKind.community,
  memberIds: ['jo'],
);

const _names = {
  'sam': 'Sam',
  'uly': 'Ulyssie',
  'jo': 'Jo',
  'fam': 'Family',
  'club': 'Club',
};

/// An event at noon on [day], with [facts].
Event _event(String id, DateTime day, Map<String, Object?> facts) =>
    Event.fromJson({
      'id': id,
      'summary': id,
      'start': localIsoTimestamp(DateTime(day.year, day.month, day.day, 12)),
      'end': localIsoTimestamp(DateTime(day.year, day.month, day.day, 13)),
      'facts': facts,
    });

Future<void> _open(
  WidgetTester tester,
  Future<void> Function(BuildContext context) open, {
  PeopleRepository? people,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = MaterialApp(
    home: Builder(
      builder: (context) =>
          TextButton(onPressed: () => open(context), child: const Text('Open')),
    ),
  );
  await tester.pumpWidget(
    people == null ? app : PeopleScope(repository: people, child: app),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group("an event's facts", () {
    test('name people and circles, a circle with its except, and send them '
        'back as the server does', () {
      final facts = Facts.fromJson({
        'with_ids': [
          'sam',
          {'person_id': 'kim', 'minutes': 10},
          {
            'circle_id': 'fam',
            'except': ['uly'],
          },
          {'circle_id': 'club', 'percent': 50},
        ],
        'for_ids': ['dance'],
      })!;

      expect(facts.withIds, ['sam', 'kim', 'fam', 'club']);
      expect(facts.withShares, const [
        PersonShare('sam'),
        PersonShare('kim', minutes: 10),
        CircleShare('fam', except: ['uly']),
        CircleShare('club', percent: 50),
      ]);
      expect(facts.withWhom, const [
        Named('sam'),
        Named('kim'),
        Named('fam', except: ['uly']),
        Named('club'),
      ]);
      expect(facts.forWhom, const [Named('dance')]);
      expect(facts.toJson()['with_ids'], [
        'sam',
        {'person_id': 'kim', 'minutes': 10},
        {
          'circle_id': 'fam',
          'except': ['uly'],
        },
        {'circle_id': 'club', 'percent': 50},
      ]);
      expect(facts.toJson()['for_ids'], ['dance']);
      expect(Facts.fromJson(facts.toJson()), facts);
      expect(
        facts,
        isNot(
          Facts.fromJson({
            ...facts.toJson(),
            'with_ids': [
              'sam',
              {'person_id': 'kim', 'minutes': 10},
              {'circle_id': 'fam'},
              {'circle_id': 'club', 'percent': 50},
            ],
          }),
        ),
      );
    });

    test('are made from whom they name, keeping the shares those had', () {
      final had = Facts.fromJson({
        'with_ids': [
          {'circle_id': 'fam', 'minutes': 30},
        ],
      });
      final facts = Facts.named(
        with_: const [
          Named('fam', except: ['uly']),
          Named('sam'),
        ],
        for_: const [Named('club')],
        from: had,
      );

      expect(facts.withShares, const [
        CircleShare('fam', except: ['uly'], minutes: 30),
        PersonShare('sam'),
      ]);
      // One named with no share, nor except, is sent as its bare id, as
      // the server takes a circle's too.
      expect(facts.toJson()['for_ids'], ['club']);
      expect(
        Facts.withSplit(facts.withSplits, const CircleShare('fam')),
        containsPair('fam', const CircleShare('fam')),
      );
      expect(
        Facts.withSplit(facts.withSplits, const PersonShare('fam')),
        isNot(contains('fam')),
      );
    });

    test('are described as the timeline says them', () {
      expect(
        Facts.named(
          with_: const [
            Named('sam'),
            Named('fam', except: ['uly']),
          ],
          for_: const [Named('club')],
        ).describe(_names),
        'With Sam, Family (except Ulyssie) · For Club',
      );
      expect(
        namedLabel(
          const Named('fam', except: ['uly', 'x']),
          (id) => _names[id] ?? id,
        ),
        'Family (except Ulyssie, x)',
      );
    });
  });

  group('a goal', () {
    test('names people and circles, a circle with its except, and sends '
        'them back so', () {
      final goal = Goal.fromJson({
        'id': 'g1',
        'title': 'Reunion',
        'with_ids': [
          'ana',
          {
            'circle_id': 'fam',
            'except': ['uly'],
          },
        ],
        'for_ids': ['club'],
      });

      expect(goal.withWhom, const [
        Named('ana'),
        Named('fam', except: ['uly']),
      ]);
      expect(goal.withIds, ['ana', 'fam']);
      expect(goal.forWhom, const [Named('club')]);
      expect(goal.toJson()['with_ids'], [
        'ana',
        {
          'circle_id': 'fam',
          'except': ['uly'],
        },
      ]);
      expect(goal.toJson()['for_ids'], ['club']);
      expect(Goal.fromJson(goal.toJson()).withWhom, goal.withWhom);
      expect(goal.involves('ana'), isTrue);
      expect(goal.involves('fam'), isTrue);
      expect(goal.involves('sam', inCircles: ['fam']), isTrue);
      expect(goal.involves('uly', inCircles: ['fam']), isFalse);
      expect(goal.involves('sam'), isFalse);
      expect(
        goalPeopleLabel(goal.withWhom, goal.forWhom, (id) => _names[id] ?? id),
        'With ana, Family (except Ulyssie) · For Club',
      );
    });

    test("a recurring goal's template and a draft name them the same way", () {
      final recurring = RecurringGoal.fromJson({
        'period': 'week',
        'with_ids': [
          {
            'circle_id': 'fam',
            'except': ['uly'],
          },
        ],
        'for_ids': ['jo'],
      })!;
      expect(recurring.withWhom, const [
        Named('fam', except: ['uly']),
      ]);
      expect(recurring.toJson()['with_ids'], [
        {
          'circle_id': 'fam',
          'except': ['uly'],
        },
      ]);
      expect(recurring.toJson()['for_ids'], ['jo']);

      final draft = GoalDraft(
        title: 'Reunion',
        day: DateTime(2026, 11, 1),
        withWhom: const [
          Named('fam', except: ['uly']),
        ],
      );
      expect(GoalDraft.fromJson(draft.toJson()).withWhom, draft.withWhom);
      expect(GoalDraft.fromJson(draft.toJson()).withIds, ['fam']);
    });
  });

  group('a circle', () {
    test('has a kind, a plain circle unless it says, and a community\'s own '
        'traits and facts are passed over', () {
      final plain = Circle.fromJson({'id': 'fam', 'name': 'Family'});
      expect(plain.kind, CircleKind.circle);
      expect(plain.isCommunity, isFalse);
      expect(plain.toJson()['kind'], 'circle');

      final community = Circle.fromJson({
        'id': 'club',
        'name': 'Club',
        'kind': 'community',
        'member_ids': ['jo'],
        'traits': {
          'select': ['kind'],
        },
        'facts': {
          'kind': {'what_matters': 'x'},
        },
        'cancelled_events': [
          {'start': '2026-10-01T12:00:00'},
        ],
      });
      expect(community.kind, CircleKind.community);
      expect(community.isCommunity, isTrue);
      expect(community.memberIds, ['jo']);
      expect(community.toJson()['kind'], 'community');
    });

    test("in memory, its kind is set when it's made, and a community takes "
        'no scoring, as the server says', () async {
      final people = InMemoryPeopleRepository();
      final club = await people.createCircle(
        const Circle(id: '', name: 'Club', kind: CircleKind.community),
      );
      expect(club.isCommunity, isTrue);
      expect((await people.people()).circles.single.kind, CircleKind.community);

      await expectLater(
        people.updateCircle(club.id, {'kind': 'circle'}),
        throwsA(
          isA<McpException>().having(
            (e) => e.message,
            'message',
            "Club's kind is 'community': a circle's kind is set when it's "
                'made, and never changed',
          ),
        ),
      );
      await expectLater(
        people.updateCircle(club.id, {'scoring': Aggregation.lowest.toJson()}),
        throwsA(
          isA<McpException>().having(
            (e) => e.message,
            'message',
            "Club is a community: its score is its own, not its members', "
                'so it takes no scoring',
          ),
        ),
      );
      // The same kind again is no change.
      expect(
        (await people.updateCircle(club.id, {'kind': 'community'})).kind,
        CircleKind.community,
      );
    });
  });

  group('who an event is with', () {
    final attendance = Attendance(circles: const [_family, _club]);

    test('a plain circle stands for its members but its except, never the '
        'user; a community for itself', () {
      expect(attendance.standsFor(const Named('fam')), ['sam', 'uly']);
      expect(attendance.standsFor(const Named('fam', except: ['uly'])), [
        'sam',
      ]);
      expect(attendance.standsFor(const Named('club')), ['club']);
      expect(attendance.standsFor(const Named('kim')), ['kim']);
      expect(attendance.plainCirclesOf('sam'), ['fam']);
      expect(attendance.plainCirclesOf('jo'), isEmpty);

      final facts = Facts.named(
        with_: const [
          Named('fam', except: ['uly']),
        ],
        for_: const [Named('club')],
      );
      expect(attendance.withAt(facts), ['sam']);
      expect(attendance.forAt(facts), ['club']);
      expect(attendance.isWith(facts, 'sam'), isTrue);
      expect(attendance.isWith(facts, 'uly'), isFalse);
      expect(attendance.isWith(facts, 'fam'), isTrue);
      expect(attendance.isFor(facts, 'jo'), isFalse);
      expect(attendance.isFor(facts, 'club'), isTrue);
    });

    test(
      "each member takes the circle's share, unless they have their own",
      () {
        final event = _event('e', DateTime(2026, 10, 1), {
          'with_ids': [
            {'circle_id': 'fam', 'minutes': 30},
            {'person_id': 'uly', 'minutes': 15},
          ],
        });
        expect(attendance.withFractions(event), {'sam': 0.5, 'uly': 0.25});
      },
    );

    test('scores a member by an event naming their circle, not one its '
        'except leaves out, and never a community\'s member', () {
      final today = DateTime(2026, 10, 2);
      final events = [
        _event('e', DateTime(2026, 10, 1), {
          'with_ids': [
            {
              'circle_id': 'fam',
              'except': ['uly'],
            },
            'club',
          ],
        }),
      ];
      const traits = [
        Trait(
          id: 'seen',
          name: 'Seen',
          parts: [
            {'kind': 'count', 'target': 1, 'interval_days': 7},
          ],
        ),
      ];
      int? score(Person person) => scorePerson(
        person,
        traits,
        DateTime(2026, 10, 1),
        today,
        events,
        circles: const [_family, _club],
      ).single.score;
      expect(score(_sam), 100);
      expect(score(_uly), 0);
      expect(score(_jo), 0);

      final scores = TraitScores.compute(
        traits: traits,
        people: const [_self, _sam, _uly, _jo],
        circles: const [_family, _club],
        events: events,
        today: today,
      );
      expect(scores.health('sam'), 100);
      expect(scores.health('uly'), 0);
      expect(scores.health('jo'), 0);
      expect(scores.digest('sam').eventsCounted, 1);
      expect(scores.digest('uly').eventsCounted, 0);
      expect(scores.digest('jo').eventsCounted, 0);
    });

    test("in memory, a person's events are those naming a circle they're "
        'in, as list_events has them', () async {
      final repository = InMemoryEventsRepository([
        _event('fam', DateTime(2026, 10, 1), {
          'with_ids': [
            {
              'circle_id': 'fam',
              'except': ['uly'],
            },
          ],
        }),
        _event('club', DateTime(2026, 10, 2), {
          'for_ids': ['club'],
        }),
      ])..circles = const [_family, _club];
      Future<List<String>> of(String id) async => [
        for (final e in await repository.personEvents(
          id,
          DateTime(2026, 9, 1),
          DateTime(2026, 11, 1),
        ))
          e.id!,
      ];
      expect(await of('sam'), ['fam']);
      expect(await of('uly'), isEmpty);
      expect(await of('jo'), isEmpty);
    });
  });

  group('the Who sheet', () {
    testWidgets('offers the circles, marked by kind, and picks who of a '
        'plain circle was not there', (tester) async {
      final people = InMemoryPeopleRepository(
        people: const [_self, _sam, _uly, _jo],
        circles: const [
          Circle(id: 'fam', name: 'Family'),
          Circle(id: 'club', name: 'Club', kind: CircleKind.community),
        ],
      );
      Facts? picked;
      await _open(
        tester,
        (context) async =>
            picked = (await showWhoWhereSheet(context, const Facts()))?.facts,
        people: people,
      );

      expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
      expect(find.text('Self'), findsNothing);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Family'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Family'), findsOneWidget);

      // Its chip picks its except: Ulyssie wasn't there.
      await tester.tap(find.widgetWithText(InputChip, 'Family'));
      await tester.pumpAndSettle();
      expect(find.text("Who of Family wasn't there"), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Self'), findsNothing);
      await tester.tap(
        find.widgetWithText(CheckboxListTile, 'Ulyssie').hitTestable(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Done').hitTestable());
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(InputChip, 'Family · except Ulyssie'),
        findsOneWidget,
      );

      // A community is picked as a person is: no except.
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Club'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InputChip, 'Club'));
      await tester.pumpAndSettle();
      expect(find.text("Who of Club wasn't there"), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(picked!.withShares, const [
        CircleShare('fam', except: ['uly']),
        CircleShare('club'),
      ]);
      expect(picked!.toJson()['with_ids'], [
        {
          'circle_id': 'fam',
          'except': ['uly'],
        },
        {'circle_id': 'club'},
      ]);
    });
  });

  group('the circle dialog', () {
    testWidgets('makes a community, set only as it is made, with no scoring', (
      tester,
    ) async {
      Map<String, Object?>? fields;
      await _open(
        tester,
        (context) => showCircleDialog(
          context,
          name: 'Club',
          members: const {'sam': 'Sam'},
          save: (saved) async => fields = saved,
        ),
      );

      expect(find.text('This circle is a community'), findsOneWidget);
      expect(find.text('How its people combine'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('How its people combine'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(fields!['kind'], 'community');
      expect(fields!.containsKey('scoring'), isFalse);
    });

    testWidgets("shows a circle's kind as it is, which can't change", (
      tester,
    ) async {
      Map<String, Object?>? fields;
      await _open(
        tester,
        (context) => showCircleDialog(
          context,
          circle: const Circle(
            id: 'club',
            name: 'Club',
            kind: CircleKind.community,
          ),
          save: (saved) async => fields = saved,
        ),
      );

      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNull);
      expect(
        find.text("Set when it was made: a circle's kind can't change."),
        findsOneWidget,
      );
      expect(find.text('How its people combine'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Note (optional)'),
        'Tuesdays',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(fields!.containsKey('kind'), isFalse);
      expect(fields!['note'], 'Tuesdays');
    });
  });
}
