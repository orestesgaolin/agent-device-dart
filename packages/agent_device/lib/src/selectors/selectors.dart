// Port of agent-device/src/daemon/selectors.ts (barrel)
library;

export 'build.dart' show buildSelectorChainForNode;
export 'is_predicates.dart'
    show
        IsPredicate,
        isSupportedPredicate,
        IsPredicateResult,
        evaluateIsPredicate;
export 'match.dart' show matchesSelector, isNodeVisible, isNodeEditable;
export 'parse.dart'
    show
        SelectorChain,
        Selector,
        SelectorTerm,
        parseSelectorChain,
        tryParseSelectorChain,
        isSelectorToken,
        splitSelectorFromArgs,
        splitIsSelectorArgs;
export 'resolve.dart'
    show
        SelectorDiagnostics,
        SelectorResolution,
        resolveSelectorChain,
        findSelectorChainMatch,
        formatSelectorFailure;
export 'selector_node.dart';
