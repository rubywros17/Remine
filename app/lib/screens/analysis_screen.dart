import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import '../data/remote/sync_status.dart';
import '../models/category.dart';
import '../widgets/app_button.dart';
import '../widgets/drawer_stage.dart';
import '../widgets/small_widgets.dart';

/// 첫 분석 화면. [status]가 있으면 실제 동기화 진행(장수·남은 예상 시간·카드가 날아드는 서랍 칸)을 보여 주고,
/// 없으면(개발용 `START_SCREEN=analysis`, 테스트) 가짜 진행값을 보여 준다.
///
/// - 진행 중: [onHome]이 있으면 "홈에서 먼저 볼래요"로 분석 중에도 홈에 나갈 수 있다(분석은 계속된다).
/// - 끝나면: 자동으로 넘어가지 않고 "N장 꺼냈어요" 완료 상태와 [홈으로] 버튼을 보여 준다.
/// - 큰 숫자는 서버 진행 수가 아니라 칸 합계다. 완료 상태도 칸을 다 채운 뒤에 보여 준다([DrawerStage.onProgress]).
///
/// 레이아웃: 상단 숫자와 하단 버튼 사이의 남는 높이를 [DrawerStage]가 쓴다. 그래도 모자라면 내용 전체가 함께 스크롤된다.
class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({
    super.key,
    this.done = 128,
    this.total = 300,
    this.status,
    this.onHome,
  });

  final int done;
  final int total;
  final SyncStatus? status;
  final VoidCallback? onHome;

  // 가짜 진행값: 지금까지 꺼낸 128장의 카테고리별 개수 (합계 128).
  static const _counts = {
    Category.shopping: 31,
    Category.info: 28,
    Category.place: 17,
    Category.entertainment: 11,
    Category.chat: 14,
    Category.schedule: 6,
    Category.etc: 21,
  };

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    if (status == null) {
      return _Body(done: done, total: total, counts: _counts, onHome: onHome);
    }
    // 다른 실행의 상태가 들어오면 큐·비행 중인 카드를 이어받지 않고 새로 시작한다.
    return _LiveAnalysis(
      key: ObjectKey(status),
      status: status,
      onHome: onHome,
    );
  }
}

class _LiveAnalysis extends StatefulWidget {
  const _LiveAnalysis({super.key, required this.status, this.onHome});

  final SyncStatus status;
  final VoidCallback? onHome;

  @override
  State<_LiveAnalysis> createState() => _LiveAnalysisState();
}

class _LiveAnalysisState extends State<_LiveAnalysis> {
  late int _landed = widget.status.counts.values.fold(0, (a, b) => a + b);
  late bool _settled = widget.status.finished;

  void _onProgress(int landed, bool settled) {
    if (landed == _landed && settled == _settled) return;
    setState(() {
      _landed = landed;
      _settled = settled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    // [Flutter 메모] ListenableBuilder는 ChangeNotifier가 알릴 때마다 builder만 다시 실행한다.
    return ListenableBuilder(
      listenable: status,
      builder: (context, _) {
        final eta = status.eta;
        return _Body(
          done: _landed,
          total: status.total,
          counts: status.counts,
          status: status,
          onProgress: _onProgress,
          finished: _settled,
          issueText: _settled ? status.issueMessage : null,
          etaText: eta != null
              ? formatEta(eta)
              : status.running
              ? '남은 시간을 계산하고 있어요'
              : null,
          waitingText: status.waitingMessage,
          onHome: widget.onHome,
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.done,
    required this.total,
    required this.counts,
    this.status,
    this.onProgress,
    this.finished = false,
    this.issueText,
    this.etaText,
    this.waitingText,
    this.onHome,
  });

  final int done;
  final int total;
  final Map<Category, int> counts;

  /// 없으면(개발용 가짜 진행값) 칸은 [counts]로 멈춰 있고 카드가 날지 않는다.
  final SyncStatus? status;
  final void Function(int landed, bool settled)? onProgress;
  final bool finished;
  final String? issueText;
  final String? etaText;
  final String? waitingText;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkGray,
      body: SafeArea(
        // 남는 높이는 가운데 스테이지가 쓰고, 모자라면 함께 스크롤된다.
        // [Flutter 메모] 스크롤 안의 Column은 높이가 무한이라 Expanded를 못 쓴다. "최소 높이 = 화면 높이"로 두고
        // IntrinsicHeight로 내용 높이를 정해 주면 Expanded가 남는 높이를 받는다.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.s16,
                    AppSpacing.screenPadding,
                    AppSpacing.s16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BrandHeader(
                            pillText: finished ? 'DONE' : 'DIGGING…',
                            color: AppColors.white,
                          ),
                          const SizedBox(height: AppSpacing.s32),
                          _Counter(
                            done: done,
                            total: total,
                            finished: finished,
                            etaText: etaText,
                          ),
                          if (issueText != null) ...[
                            const SizedBox(height: AppSpacing.s8),
                            Text(
                              issueText!,
                              style: AppText.body.copyWith(
                                fontSize: 14,
                                color: AppColors.lemon,
                              ),
                            ),
                          ],
                          if (waitingText != null) ...[
                            const SizedBox(height: AppSpacing.s16),
                            _WorkingNote(text: waitingText!),
                          ],
                          if (!finished) ...[
                            const SizedBox(height: AppSpacing.s12),
                            Text(
                              keepScreenOnHint,
                              style: AppText.caption.copyWith(
                                color: AppColors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      Expanded(
                        child: DrawerStage(
                          status: status,
                          counts: counts,
                          onProgress: onProgress,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (onHome != null) ...[
                            Center(
                              child: AppButton(
                                label: finished ? '홈으로' : '홈에서 먼저 볼래요',
                                onTap: onHome,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s16),
                          ],
                          const PrivacyNote(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 큰 진행 숫자. 진행 중에는 "N / M장 꺼냈어요", 끝나면 "N장 꺼냈어요".
class _Counter extends StatelessWidget {
  const _Counter({
    required this.done,
    required this.total,
    required this.finished,
    required this.etaText,
  });

  final int done;
  final int total;
  final bool finished;
  final String? etaText;

  /// 끝났는데 꺼낸 게 없을 때(새 캡처 없음·서버에 닿지 못함).
  static const _noneText = '새로 꺼낼 캡처가 없어요';

  String get _finishedText => done == 0 ? _noneText : '$done장 꺼냈어요';

  @override
  Widget build(BuildContext context) {
    // 큰 진행 숫자: 셀라돈 on 다크그레이 (대비 4.43:1)
    return Semantics(
      label: finished ? _finishedText : '$total장 중 $done장 꺼냈어요',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$done',
              style: AppText.numHero(color: AppColors.celadon, size: 128),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            finished
                ? (done == 0 ? _finishedText : '장 꺼냈어요')
                : '/ $total장 꺼냈어요',
            style: AppText.sectionTitle.copyWith(color: AppColors.white),
          ),
          if (!finished && etaText != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              etaText!,
              style: AppText.body.copyWith(color: AppColors.celadonSoft),
            ),
          ],
        ],
      ),
    );
  }
}

/// 진행 중 안내. 화면이 꺼지면 앱이 백그라운드로 가서 동기화가 멈춘다(앱은 이 화면 동안 화면 꺼짐도 막는다, [SyncGate]).
const keepScreenOnHint = '정리하는 동안 화면을 켜 두세요';

/// 보안 문구: 박스 없이 작은 회색 글씨 한 줄(자물쇠 아이콘 작게). 좁은 화면이나 큰 글자에서는 줄바꿈된다.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key});

  static const text = '은행·메신저·민감한 캡처는 기기 밖으로 전송되지 않아요';

  @override
  Widget build(BuildContext context) {
    final grey = AppColors.white.withValues(alpha: 0.55);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(LucideIcons.lock, size: 12, color: grey),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(fontSize: 12, color: grey),
          ),
        ),
      ],
    );
  }
}

/// "N장을 분류하는 중" 안내. 서버 응답을 기다리는 동안 숫자가 안 바뀌어도 멈춘 게 아니라는 걸 막대가 움직여 보여 준다.
/// 모션 줄이기 설정이면 움직이는 막대 없이 글자만 보여 준다.
class _WorkingNote extends StatelessWidget {
  const _WorkingNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!AppMotion.reduced(context)) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: const LinearProgressIndicator(
                minHeight: 4,
                color: AppColors.celadon,
                backgroundColor: Color(0x33FFFFFF),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          Text(
            text,
            style: AppText.body.copyWith(fontSize: 14, color: AppColors.white),
          ),
        ],
      ),
    );
  }
}
