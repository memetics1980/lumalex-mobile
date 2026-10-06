import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictionary/screens/aggregate_article_page.dart';

void main() {
  test('selected-dictionary presentation shows only the active section', () {
    final css = aggregateArticlePresentationCss(
      AggregateArticlePresentation.selectedDictionary,
    );

    expect(
      css,
      contains('body.selected-dictionary .dictionary-section { display: none'),
    );
    expect(css, contains('.dictionary-section.active { display: block'));
    expect(css, contains('.dictionary-header { display: none'));
  });

  test('dictionary tab switching preserves scroll without animation', () {
    final javascript = aggregateDictionarySelectionJavascript();

    expect(javascript, contains('dictionaryScrollOffsets.set(current.id'));
    expect(javascript, contains("current.classList.remove('active')"));
    expect(javascript, contains("next.classList.add('active')"));
    expect(javascript, contains("behavior: 'auto'"));
    expect(javascript, isNot(contains("behavior: 'smooth'")));
  });

  test('continuous presentation adds no tab-only hiding rules', () {
    expect(
      aggregateArticlePresentationCss(
        AggregateArticlePresentation.continuous,
      ),
      isEmpty,
    );
  });

  test('iframe selection is forwarded with its dictionary token', () {
    final javascript = aggregateDictionarySelectionObserverJavascript();

    expect(javascript, contains("String(doc.getSelection() || '').trim()"));
    expect(
      javascript,
      contains("bridge.callHandler('aggregateDictionarySelection', token"),
    );
    expect(javascript, contains("doc.addEventListener('selectionchange'"));
    expect(javascript, contains("doc.addEventListener('contextmenu'"));
  });
}
