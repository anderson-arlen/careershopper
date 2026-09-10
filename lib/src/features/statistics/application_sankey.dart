import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/job_statistics.dart';

class ApplicationSankey extends StatefulWidget {
  const ApplicationSankey({super.key, required this.statistics});
  final JobStatistics statistics;

  @override
  State<ApplicationSankey> createState() => _ApplicationSankeyState();
}

class _ApplicationSankeyState extends State<ApplicationSankey> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodes = widget.statistics.sankeyNodes;
    final links = widget.statistics.sankeyLinks;
    final textScale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(14) / 14,
    );
    final labelHeight = 64 * textScale;
    final labelWidth = 190 * textScale;
    final top = labelHeight + 16;
    final gap = labelHeight + 20;

    final unit = widget.statistics.found == 0
        ? 0.0
        : 304 / widget.statistics.found;
    final stageColors = [
      theme.colorScheme.primary,
      Color(0xFFB93846),
      Color(0xFFEBA253),
      Color(0xFF39B7A5),
      Color(0xFF7252A3),
    ];
    final colors = {
      for (final node in nodes)
        node.id: node.remainder
            ? (node.terminal
                  ? theme.colorScheme.outline
                  : theme.colorScheme.primary)
            : stageColors[node.column],
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(1420 * textScale, constraints.maxWidth);
        final columnWidth = (width - labelWidth) / 5;
        final bounds = <String, Rect>{};
        var height = top;
        for (var column = 0; column <= 5; column++) {
          var y = top;
          for (final node in nodes.where((node) => node.column == column)) {
            bounds[node.id] = Rect.fromLTWH(
              column * columnWidth,
              y,
              16,
              node.count * unit,
            );
            y += node.count * unit + gap;
          }
          height = math.max(height, y - gap + 16);
        }
        return Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SankeyPainter(
                        links: links,
                        bounds: bounds,
                        colors: colors,
                        unit: unit,
                      ),
                    ),
                  ),
                  for (final node in nodes)
                    Positioned(
                      key: ValueKey('sankey-${node.id}'),
                      left: bounds[node.id]!.left,
                      top: bounds[node.id]!.top - labelHeight - 8,
                      width: labelWidth,
                      child: Tooltip(
                        message:
                            '${_nodeDescription(node, nodes, links)}: ${node.count} jobs',
                        child: Semantics(
                          label:
                              '${_nodeDescription(node, nodes, links)}: ${node.count}',
                          excludeSemantics: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (node.remainder && !node.terminal) ...[
                                    Icon(
                                      Icons.schedule,
                                      size: 16,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Expanded(
                                    child: Text(
                                      node.label,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${node.count}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _nodeDescription(
  JobFlowNode node,
  List<JobFlowNode> nodes,
  List<JobFlowLink> links,
) {
  if (!node.remainder) return node.label;
  final parentId = links.singleWhere((link) => link.target == node.id).source;
  final parent = nodes.singleWhere((n) => n.id == parentId);
  return '${parent.label}: ${node.label}${node.terminal ? '' : ' (in progress)'}';
}

class _SankeyPainter extends CustomPainter {
  const _SankeyPainter({
    required this.links,
    required this.bounds,
    required this.colors,
    required this.unit,
  });
  final List<JobFlowLink> links;
  final Map<String, Rect> bounds;
  final Map<String, Color> colors;
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    final outgoing = <String, double>{};
    final incoming = <String, double>{};
    for (final link in links) {
      if (link.count == 0) continue;
      final source = bounds[link.source]!;
      final target = bounds[link.target]!;
      final sourceY = source.top + (outgoing[link.source] ?? 0);
      final targetY = target.top + (incoming[link.target] ?? 0);
      final thickness = link.count * unit;
      final bend = (target.left - source.right) * 0.5;
      final path = Path()
        ..moveTo(source.right, sourceY)
        ..cubicTo(
          source.right + bend,
          sourceY,
          target.left - bend,
          targetY,
          target.left,
          targetY,
        )
        ..lineTo(target.left, targetY + thickness)
        ..cubicTo(
          target.left - bend,
          targetY + thickness,
          source.right + bend,
          sourceY + thickness,
          source.right,
          sourceY + thickness,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = colors[link.target]!.withValues(alpha: 0.4),
      );
      outgoing[link.source] = (outgoing[link.source] ?? 0) + thickness;
      incoming[link.target] = (incoming[link.target] ?? 0) + thickness;
    }
    for (final entry in bounds.entries) {
      // Zero-count stages have only a marker; no flow width is invented.
      final rect = entry.value;
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left,
          rect.top,
          rect.width,
          math.max(1, rect.height),
        ),
        Paint()..color = colors[entry.key]!,
      );
    }
  }

  @override
  bool shouldRepaint(_SankeyPainter oldDelegate) =>
      oldDelegate.links != links ||
      oldDelegate.bounds != bounds ||
      oldDelegate.colors != colors ||
      oldDelegate.unit != unit;
}
