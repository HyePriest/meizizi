import 'package:flutter/material.dart';

import '../data/models.dart';
import '../pages/image_page.dart';
import '../pages/reading_page.dart';
import 'post_widgets.dart';

class ThreadThumbnails extends StatelessWidget {
  const ThreadThumbnails({super.key, required this.thread});
  final Json thread;
  @override
  Widget build(BuildContext context) {
    final video = threadVideo(thread);
    if (video.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: VideoPreview(
          info: video,
          onTap: videoSource(video).isNotEmpty
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReadingPage(
                      threadId: firstText([thread['id'], thread['tid']]),
                      title: firstText([thread['title']]),
                      forum: threadForumName(thread),
                    ),
                  ),
                ),
        ),
      );
    }
    final images = threadImages(thread);
    if (images.isEmpty) return const SizedBox.shrink();
    final visible = images.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: AspectRatio(
                aspectRatio: visible.length == 1 ? 1.8 : 1,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ImagePage(
                        url: '${visible[i]['original']}',
                        urls: images.map((p) => '${p['original']}').toList(),
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          '${visible[i]['thumbnail']}',
                          fit: BoxFit.cover,
                          cacheWidth: 450,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0xffeeeeee),
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        if (i == 2 && images.length > 3)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              color: Colors.black54,
                              child: Text(
                                '+${images.length - 3}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
