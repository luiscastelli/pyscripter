{-----------------------------------------------------------------------------
 Unit Name: frmVariables
 Author:    Kiriakos Vlahos
 Date:      09-Mar-2005
 Purpose:   Variables Window
 History:
-----------------------------------------------------------------------------}

unit frmVariables;

interface

uses
  WinApi.Windows,
  WinApi.Messages,
  System.UITypes,
  System.SysUtils,
  System.Variants,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Menus,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  JvComponentBase,
  JvDockControlForm,
  JvAppStorage,
  SpTBXDkPanels,
  SpTBXSkins,
  SpTBXPageScroller,
  SpTBXItem,
  SpTBXControls,
  VTHeaderPopup,
  VirtualTrees,
  frmIDEDockWin,
  cPyBaseDebugger;

type
  TVariablesWindow = class(TIDEDockWindow, IJvAppStorageHandler)
    VTHeaderPopupMenu: TVTHeaderPopupMenu;
    VariablesTree: TVirtualStringTree;
    DocPanel: TSpTBXPageScroller;
    SpTBXSplitter: TSpTBXSplitter;
    reInfo: TRichEdit;
    procedure VariablesTreeChange(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure FormCreate(Sender: TObject);
    procedure VariablesTreeInitNode(Sender: TBaseVirtualTree; ParentNode,
      Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
    procedure VariablesTreeGetImageIndex(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
      var Ghosted: Boolean; var ImageIndex: TImageIndex);
    procedure VariablesTreeGetText(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
      var CellText: string);
    procedure FormActivate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure VariablesTreePaintText(Sender: TBaseVirtualTree;
      const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType);
    procedure VariablesTreeInitChildren(Sender: TBaseVirtualTree;
      Node: PVirtualNode; var ChildCount: Cardinal);
    procedure reInfoResizeRequest(Sender: TObject; Rect: TRect);
  private
    { Private declarations }
    CurrentModule, CurrentFunction : string;
    GlobalsNameSpace, LocalsNameSpace : TBaseNameSpaceItem;
  protected
    // IJvAppStorageHandler implementation
    procedure ReadFromAppStorage(AppStorage: TJvCustomAppStorage; const BasePath: string);
    procedure WriteToAppStorage(AppStorage: TJvCustomAppStorage; const BasePath: string);
  public
    { Public declarations }
    procedure ClearAll;
    procedure UpdateWindow;
  end;

var
  VariablesWindow: TVariablesWindow = nil;

implementation

uses
  System.Math,
  Vcl.Themes,
  JvJVCLUtils,
  PythonEngine,
  JvGnugettext,
  StringResources,
  dmCommands,
  frmCallStack,
  uCommonFunctions,
  cVirtualStringTreeHelper,
  cPyControl;

{$R *.dfm}
Type
  PPyObjRec = ^TPyObjRec;
  TPyObjRec = record
    NameSpaceItem : TBaseNameSpaceItem;
  end;

procedure TVariablesWindow.FormCreate(Sender: TObject);
begin
  inherited;
  // Let the tree know how much data space we need.
  VariablesTree.NodeDataSize := SizeOf(TPyObjRec);
end;

procedure TVariablesWindow.VariablesTreeInitChildren(Sender: TBaseVirtualTree;
  Node: PVirtualNode; var ChildCount: Cardinal);
var
  Data: PPyObjRec;
begin
  Data := VariablesTree.GetNodeData(Node);
  ChildCount := Data.NameSpaceItem.ChildCount;
end;

procedure TVariablesWindow.VariablesTreeInitNode(Sender: TBaseVirtualTree;
  ParentNode, Node: PVirtualNode;
  var InitialStates: TVirtualNodeInitStates);
var
  Data, ParentData: PPyObjRec;
begin
  Data := VariablesTree.GetNodeData(Node);
  if VariablesTree.GetNodeLevel(Node) = 0 then begin
    Assert(Node.Index <= 1);
    if CurrentModule <> '' then begin
      if Node.Index = 0 then begin
        Assert(Assigned(GlobalsNameSpace));
        Data.NameSpaceItem := GlobalsNameSpace;
        InitialStates := [ivsHasChildren];
      end else if Node.Index = 1 then begin
        Assert(Assigned(LocalsNameSpace));
        Data.NameSpaceItem := LocalsNameSpace;
        InitialStates := [ivsExpanded, ivsHasChildren];
      end;
    end else begin
      Assert(Node.Index = 0);
      Assert(Assigned(GlobalsNameSpace));
      Data.NameSpaceItem := GlobalsNameSpace;
      InitialStates := [ivsExpanded, ivsHasChildren];
    end;
  end else begin
    ParentData := VariablesTree.GetNodeData(ParentNode);
    Data.NameSpaceItem := ParentData.NameSpaceItem.ChildNode[Node.Index];
    if Data.NameSpaceItem.ChildCount > 0 then
      InitialStates := [ivsHasChildren]
    else
      InitialStates := [];
  end;
end;

procedure TVariablesWindow.VariablesTreePaintText(Sender: TBaseVirtualTree;
  const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  TextType: TVSTTextType);
var
  Data : PPyObjRec;
begin
  Data := VariablesTree.GetNodeData(Node);
  if Assigned(Data) then
    if nsaChanged in Data.NameSpaceItem.Attributes then
      TargetCanvas.Font.Color := clRed
    else if nsaNew in Data.NameSpaceItem.Attributes then
      TargetCanvas.Font.Color := StyleServices.GetSystemColor(clHotlight);
end;

procedure TVariablesWindow.ReadFromAppStorage(AppStorage: TJvCustomAppStorage;
  const BasePath: string);
Var
  TempWidth : integer;
begin
  TempWidth := PPIScaled(AppStorage.ReadInteger(BasePath+'\DocPanelWidth', DocPanel.Width));
  DocPanel.Width := Min(TempWidth,  Max(Width-PPIScaled(100), PPIScaled(3)));
  if AppStorage.ReadBoolean(BasePath+'\Types Visible') then
    VariablesTree.Header.Columns[1].Options := VariablesTree.Header.Columns[1].Options + [coVisible]
  else
    VariablesTree.Header.Columns[1].Options := VariablesTree.Header.Columns[1].Options - [coVisible];
  VariablesTree.Header.Columns[0].Width :=
    PPIScaled(AppStorage.ReadInteger(BasePath+'\Names Width', 160));
  VariablesTree.Header.Columns[1].Width :=
    PPIScaled(AppStorage.ReadInteger(BasePath+'\Types Width', 100));
end;

procedure TVariablesWindow.reInfoResizeRequest(Sender: TObject; Rect: TRect);
begin
  Rect.Height := Max(Rect.Height, reInfo.Parent.ClientHeight);
  reInfo.BoundsRect := Rect;
end;

procedure TVariablesWindow.WriteToAppStorage(AppStorage: TJvCustomAppStorage;
  const BasePath: string);
begin
  AppStorage.WriteInteger(BasePath+'\DocPanelWidth', PPIUnScaled(DocPanel.Width));
  AppStorage.WriteBoolean(BasePath+'\Types Visible', coVisible in VariablesTree.Header.Columns[1].Options);
  AppStorage.WriteInteger(BasePath+'\Names Width',
    PPIUnScaled(VariablesTree.Header.Columns[0].Width));
  AppStorage.WriteInteger(BasePath+'\Types Width',
    PPIUnScaled(VariablesTree.Header.Columns[1].Width));
end;

procedure TVariablesWindow.VariablesTreeGetImageIndex(
  Sender: TBaseVirtualTree; Node: PVirtualNode; Kind: TVTImageKind;
  Column: TColumnIndex; var Ghosted: Boolean; var ImageIndex: TImageIndex);
var
  Data : PPyObjRec;
begin
  if (Column = 0) and (Kind in [ikNormal, ikSelected]) then begin
    Data := VariablesTree.GetNodeData(Node);
    if Data.NameSpaceItem.IsDict then
      ImageIndex := Integer(TCodeImages.Namespace)
    else if Data.NameSpaceItem.IsModule then
      ImageIndex := Integer(TCodeImages.Module)
    else if Data.NameSpaceItem.IsMethod then
      ImageIndex := Integer(TCodeImages.Method)
    else if Data.NameSpaceItem.IsFunction then
      ImageIndex := Integer(TCodeImages.Func)
    else if Data.NameSpaceItem.IsClass or Data.NameSpaceItem.Has__dict__ then
        ImageIndex := Integer(TCodeImages.Klass)
    else if (Data.NameSpaceItem.ObjectType = 'list') or (Data.NameSpaceItem.ObjectType = 'tuple') then
      ImageIndex := Integer(TCodeImages.List)
    else begin
      if Assigned(Node.Parent) and (Node.Parent <> VariablesTree.RootNode) and
        (PPyObjRec(VariablesTree.GetNodeData(Node.Parent)).NameSpaceItem.IsDict
          or PPyObjRec(VariablesTree.GetNodeData(Node.Parent)).NameSpaceItem.IsModule)
      then
        ImageIndex := Integer(TCodeImages.Variable)
      else
        ImageIndex := Integer(TCodeImages.Field);
    end;
  end else
    ImageIndex := -1;
end;

procedure TVariablesWindow.VariablesTreeGetText(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
  var CellText: string);
var
  Data : PPyObjRec;
begin
  if TextType <> ttNormal then Exit;
  Data := VariablesTree.GetNodeData(Node);
  if not Assigned(Data) or not Assigned(Data.NameSpaceItem) then
    Exit;

  CellText := '';
  case Column of
    0 : CellText := Data.NameSpaceItem.Name;
    1 : with GetPythonEngine do
          CellText := Data.NameSpaceItem.ObjectType;
    2 : begin
          try
            CellText := Data.NameSpaceItem.Value;
          except
            CellText := '';
          end;
        end;
  end;
end;

procedure TVariablesWindow.UpdateWindow;
Var
  CurrentFrame : TBaseFrameInfo;
  SameFrame : boolean;
  RootNodeCount : Cardinal;
  OldGlobalsNameSpace, OldLocalsNamespace : TBaseNameSpaceItem;
  Cursor : IInterface;
begin
  if not (Assigned(CallStackWindow) and
          Assigned(PyControl.ActiveInterpreter) and
          Assigned(PyControl.ActiveDebugger)) then begin   // Should not happen!
     ClearAll;
     Exit;
  end;

  if PyControl.IsRunning then begin
    // should not update
    VariablesTree.Enabled := False;
    Exit;
  end else
    VariablesTree.Enabled := True;

  // Get the selected frame
  CurrentFrame := CallStackWindow.GetSelectedStackFrame;

  SameFrame := (not Assigned(CurrentFrame) and
                (CurrentModule = '') and
                (CurrentFunction = '')) or
                (Assigned(CurrentFrame) and
                (CurrentModule = CurrentFrame.FileName) and
                (CurrentFunction = CurrentFrame.FunctionName));

  OldGlobalsNameSpace := GlobalsNameSpace;
  OldLocalsNamespace := LocalsNameSpace;
  GlobalsNameSpace := nil;
  LocalsNameSpace := nil;

  // Turn off Animation to speed things up
  VariablesTree.TreeOptions.AnimationOptions :=
    VariablesTree.TreeOptions.AnimationOptions - [toAnimatedToggle];

  if Assigned(CurrentFrame) then begin
    CurrentModule := CurrentFrame.FileName;
    CurrentFunction := CurrentFrame.FunctionName;
    // Set the initial number of nodes.
    GlobalsNameSpace := PyControl.ActiveDebugger.GetFrameGlobals(CurrentFrame);
    LocalsNameSpace := PyControl.ActiveDebugger.GetFrameLocals(CurrentFrame);
    if Assigned(GlobalsNameSpace) and Assigned(LocalsNameSpace) then
      RootNodeCount := 2
    else
      RootNodeCount := 0;
  end else begin
    CurrentModule := '';
    CurrentFunction := '';
    try
      GlobalsNameSpace := PyControl.ActiveInterpreter.GetGlobals;
      RootNodeCount := 1;
    except
      RootNodeCount := 0;
    end;
  end;

  if (RootNodeCount > 0) and SameFrame and (RootNodeCount = VariablesTree.RootNodeCount) then begin
    Cursor := WaitCursor;
    if Assigned(GlobalsNameSpace) and Assigned(OldGlobalsNameSpace) then
      GlobalsNameSpace.CompareToOldItem(OldGlobalsNameSpace);
    if Assigned(LocalsNameSpace) and Assigned(OldLocalsNameSpace) then
      LocalsNameSpace.CompareToOldItem(OldLocalsNameSpace);
    VariablesTree.BeginUpdate;
    try
      VariablesTree.ReinitInitializedChildren(nil, True);
      VariablesTree.InvalidateToBottom(VariablesTree.GetFirstVisible);
    finally
      VariablesTree.EndUpdate;
    end;
  end else begin
    VariablesTree.Clear;
    VariablesTree.RootNodeCount := RootNodeCount;
  end;
  FreeAndNil(OldGlobalsNameSpace);
  FreeAndNil(OldLocalsNameSpace);


  VariablesTree.TreeOptions.AnimationOptions :=
    VariablesTree.TreeOptions.AnimationOptions + [toAnimatedToggle];
  VariablesTreeChange(VariablesTree, nil);
end;

procedure TVariablesWindow.ClearAll;
begin
  VariablesTree.Clear;
  FreeAndNil(GlobalsNameSpace);
  FreeAndNil(LocalsNameSpace);
end;

procedure TVariablesWindow.FormActivate(Sender: TObject);
begin
  inherited;
  if not VariablesTree.Enabled then VariablesTree.Clear;

  if CanActuallyFocus(VariablesTree) then
    VariablesTree.SetFocus;
  //PostMessage(VariablesTree.Handle, WM_SETFOCUS, 0, 0);
end;

procedure TVariablesWindow.FormDestroy(Sender: TObject);
begin
  VariablesWindow := nil;
  ClearAll;
  inherited;
end;

procedure TVariablesWindow.VariablesTreeChange(Sender: TBaseVirtualTree;
  Node: PVirtualNode);
Var
  NameSpace,
  ObjectName,
  ObjectType,
  ObjectValue,
  DocString : string;
  Data : PPyObjRec;
begin
  // Get the selected frame
  if CurrentModule <> '' then
    NameSpace := Format(_(SNamespaceFormat), [CurrentFunction, CurrentModule])
  else
    NameSpace := 'Interpreter globals';

  reInfo.Clear;
  AddFormatText(reInfo, _('Namespace') + ': ', [fsBold]);
  AddFormatText(reInfo, NameSpace, [fsItalic]);
  if Assigned(Node) and (vsSelected in Node.States) then begin
    Data := VariablesTree.GetNodeData(Node);
    ObjectName := Data.NameSpaceItem.Name;
    ObjectType := Data.NameSpaceItem.ObjectType;
    ObjectValue := Data.NameSpaceItem.Value;
    DocString :=  Data.NameSpaceItem.DocString;

    AddFormatText(reInfo, SLineBreak+_('Name')+': ', [fsBold]);
    AddFormatText(reInfo, ObjectName, [fsItalic]);
    AddFormatText(reInfo, SLineBreak + _('Type') + ': ', [fsBold]);
    AddFormatText(reInfo, ObjectType);
    AddFormatText(reInfo, SLineBreak + _('Value') + ':' + SLineBreak, [fsBold]);
    AddFormatText(reInfo, ObjectValue);
    AddFormatText(reInfo, SLineBreak + _('DocString') + ':' + SLineBreak, [fsBold]);
    AddFormatText(reInfo, Docstring);
  end;
end;

end.


