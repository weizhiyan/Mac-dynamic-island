using System;

namespace DynamicIsland.Core;

/// <summary>快捷应用条目。Id 用于标识与拖拽排序；Path 指向可执行文件或快捷方式。</summary>
public sealed class AppItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string? Path { get; set; }
    public int Order { get; set; }
}