import 'package:flutter/material.dart';

import 'day_timeline.dart' show reviewColors;
import 'proposal_review.dart' show ProposalDetailPage;

/// One thing guided review steps to: the [index]th on [page] of the
/// proposal's details, known by [key] -- which says what it is, as it
/// is now, so it's to review again once Claude changes it.
typedef ReviewStep = ({ProposalDetailPage page, int index, String key});

/// The pages guided review steps through, in order: follow-through is
/// left for whoever wants it.
const guidedPages = [
  ProposalDetailPage.notes,
  ProposalDetailPage.goals,
  ProposalDetailPage.added,
  ProposalDetailPage.stories,
  ProposalDetailPage.facts,
  ProposalDetailPage.claude,
];

/// The step after [current] in [steps] not yet [seen] -- or, past the
/// last, the first not seen -- or null once all have been.
ReviewStep? nextToReview(
  List<ReviewStep> steps,
  Set<String> seen, {
  String? current,
}) {
  final at = current == null ? -1 : steps.indexWhere((s) => s.key == current);
  for (final i in [
    for (var i = at + 1; i < steps.length; i++) i,
    for (var i = 0; i <= at && i < steps.length; i++) i,
  ]) {
    if (!seen.contains(steps[i].key)) return steps[i];
  }
  return null;
}

/// The step before [current] in [steps], seen or not; null for the
/// first, or with none shown.
ReviewStep? previousToReview(List<ReviewStep> steps, {String? current}) {
  final at = current == null ? -1 : steps.indexWhere((s) => s.key == current);
  return at > 0 ? steps[at - 1] : null;
}

/// [steps], a section a page: its name, and whether each of its steps
/// has been [seen].
List<ReviewSection> reviewSections(List<ReviewStep> steps, Set<String> seen) =>
    [
      for (final page in guidedPages)
        if (steps.where((s) => s.page == page).toList() case final mine
            when mine.isNotEmpty)
          (page: page, seen: [for (final s in mine) seen.contains(s.key)]),
    ];

/// A page's steps in guided review, and which have been seen.
typedef ReviewSection = ({ProposalDetailPage page, List<bool> seen});

/// What [page] is called in guided review's progress.
String reviewPageName(ProposalDetailPage page) => switch (page) {
  ProposalDetailPage.notes => 'Notes',
  ProposalDetailPage.goals => 'Goals',
  ProposalDetailPage.added => 'Added',
  ProposalDetailPage.stories => 'Stories',
  ProposalDetailPage.facts => 'Facts',
  ProposalDetailPage.claude => 'Unsure',
  ProposalDetailPage.followThrough => 'Follow-through',
};

/// How far guided review has got: each of [sections] by name, with a
/// segment a step, filled once it's been seen -- [current]'s name bold.
/// Tapping one calls [onTap] with its page.
class ReviewProgress extends StatelessWidget {
  const ReviewProgress({
    super.key,
    required this.sections,
    this.current,
    this.onTap,
  });

  final List<ReviewSection> sections;
  final ProposalDetailPage? current;
  final ValueChanged<ProposalDetailPage>? onTap;

  /// The most steps drawn one by one: more are drawn as one bar.
  static const _mostSegments = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final done = reviewColors(colors).line;
    final left = colors.outlineVariant;
    Widget segments(List<bool> seen) {
      if (seen.length > _mostSegments) {
        final share = seen.where((s) => s).length / seen.length;
        return SizedBox(
          width: 48,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: share,
              color: done,
              backgroundColor: left,
            ),
          ),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, s) in seen.indexed)
            Container(
              width: 8,
              height: 4,
              margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
              decoration: BoxDecoration(
                color: s ? done : left,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      );
    }

    // One line, scrolled sideways if it must be, so it takes no more
    // room from what's reviewed.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final section in sections)
            Semantics(
              button: onTap != null,
              label:
                  '${reviewPageName(section.page)}: '
                  '${section.seen.where((s) => s).length} of '
                  '${section.seen.length} reviewed',
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap == null ? null : () => onTap!(section.page),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        reviewPageName(section.page),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: section.page == current
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                          fontWeight: section.page == current
                              ? FontWeight.w700
                              : null,
                        ),
                      ),
                      const SizedBox(width: 4),
                      segments(section.seen),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
