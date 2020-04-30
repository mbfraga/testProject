#include <dummy_DropDown.h>

#include <QListView>
#include <QEvent>

#include <iostream>


namespace dummy {

//== DropDownListBox ==================================================

DropDownListBox::DropDownListBox(QObject* parent)
    : QAbstractListModel(parent)
{}

DropDownListBox::~DropDownListBox() {}

void DropDownListBox::showDropDown(const std::vector<std::string>& matches, QWidget* parent)
{
  if (!mListView) {
    mListView = new QListView(nullptr);
    mListView->setFocusPolicy(Qt::NoFocus);
    mListView->setWindowFlag(Qt::Popup);

    mListView->setEditTriggers(QAbstractItemView::NoEditTriggers);
    mListView->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    mListView->setSelectionBehavior(QAbstractItemView::SelectRows);
    mListView->setSelectionMode(QAbstractItemView::SingleSelection);
    mListView->setResizeMode(QListView::ResizeMode::Adjust);
    mListView->setUniformItemSizes(true);
    mListView->installEventFilter(this);

    mMatches = matches;

    mListView->setModel(this);

    //auto delegate = new MatchItemDelegate(mListView);
    //mListView->setItemDelegate(delegate);
    //mListView->releaseMouse();
    //mListView->releaseKeyboard();
  }
  else {
    beginResetModel();
    mMatches = matches;
    endResetModel();
  }

  mListView->setFocusProxy(parent);

  auto g = parent->geometry();
  g.moveTopLeft(parent->mapToGlobal(g.bottomLeft()));
  g.setHeight(mListView->sizeHint().height());
  mListView->setGeometry(g);

  if (!mListView->isVisible()) {
    mListView->show();
  }
}

void DropDownListBox::hideDropDown()
{
  mListView->hide();
}

int DropDownListBox::rowCount(const QModelIndex& /*parent*/) const
{
  return static_cast<int>(mMatches.size());
}

QVariant DropDownListBox::data(const QModelIndex& index, int /*role*/) const
{
  auto row = static_cast<size_t>(index.row());
  if (row >= mMatches.size()) {
    return {};
  }

  return QVariant::fromValue(QString::fromStdString(mMatches[row]));
}

bool DropDownListBox::eventFilter(QObject* watched, QEvent* event)
{
  hideDropDown();

  std::cout << event->type() << std::endl;

  switch (event->type()) {
  case QEvent::MouseButtonRelease: {
    std::cout << "MOUSE Release" << std::endl;
    if (!mListView->underMouse()) {
      std::cout << "HIDE" << std::endl;
      hideDropDown();
      return true;
    }
    break;
  }
  default:
    break;
  }
  return QAbstractItemModel::eventFilter(watched, event);
}

bool DropDownListBox::event(QEvent* event)
{
  return QObject::event(event);
}

} // namespace dummy
