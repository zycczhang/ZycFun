import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// --- 通用UI组件：焦点处理（TV核心） ---
class FocusableWidget extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback onTap;
  final FocusNode? focusNode; // 新增：允许传入外部 FocusNode

  const FocusableWidget({
    super.key,
    required this.builder,
    required this.onTap,
    this.focusNode
  });

  @override
  State<FocusableWidget> createState() => _FocusableWidgetState();
}

class _FocusableWidgetState extends State<FocusableWidget> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode, // 绑定传入的 node
      onFocusChange: (hasFocus) => setState(() => _isFocused = hasFocus),
      onKeyEvent: (node, event) {
        if (_isFocused && event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: widget.builder(context, _isFocused),
      ),
    );
  }
}

// --- UI组件：左侧导航栏（增加选中状态回调） ---
class SideNavigation extends StatelessWidget {
  final int selectedNavIndex;
  final Function(int) onNavSelected;

  const SideNavigation({
    super.key,
    required this.selectedNavIndex,
    required this.onNavSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      color: const Color(0xFF1C1C1C),
      child: Column(
        children: [
          const SizedBox(height: 40), // 顶部固定间距
          // 核心修改：用Expanded包裹需要居中的图标，并设置居中对齐
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, // 垂直居中
              children: [
                _buildNavIcon(0, Icons.search), // 0: 搜索
                _buildNavIcon(1, Icons.person_outline), // 1: 个人
                _buildNavIcon(2, Icons.home, isSelected: true), // 2: 首页
              ],
            ),
          ),
          // 底部的设置图标区域（保持原有位置）
          _buildNavIcon(3, Icons.settings), // 3: 设置
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNavIcon(int index, IconData icon, {bool isSelected = false}) {
    bool currentSelected = selectedNavIndex == index;
    return FocusableWidget(
      builder: (context, focused) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: focused ? Colors.white10 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: focused || currentSelected ? Colors.white : Colors.grey,
            size: 30,
          ),
        );
      },
      onTap: () => onNavSelected(index),
    );
  }
}

// --- UI组件：顶部标签栏 ---
class TopHeader extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTabChanged;
  final FocusNode? firstTabNode; // 新增
  final bool showPrivate; // 1. 新增：控制是否显示私密栏

  const TopHeader({
    super.key,
    required this.selectedIndex,
    required this.onTabChanged,
    this.firstTabNode,
    this.showPrivate = false, // 2. 新增：默认为 false
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildTopTab(0, "动画", node: firstTabNode), // 仅给第一个标签绑定 node
          _buildTopTab(1, "综艺"),
          _buildTopTab(2, "电影"),
          _buildTopTab(3, "电视剧"),
          if (showPrivate)
            _buildTopTab(4, "绅士专区"),
        ],
      ),
    );
  }

  Widget _buildTopTab(int index, String title, {FocusNode? node}) {
    bool isSelected = selectedIndex == index;

    return FocusableWidget(
      focusNode: node, // 绑定
      builder: (context, focused) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: focused ? Colors.white : (isSelected ? Colors.white24 : Colors.transparent),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: focused ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
      onTap: () => onTabChanged(index),
    );
  }
}