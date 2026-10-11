import 'package:app/features/chat/widgets/markdown/md_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('image-led bullets become a picture list', () {
    const src =
        'Main types:\n\n'
        '- {{image:RNN architecture diagram}} **Recurrent Neural Network (RNN)** '
        '– processes one element at a time [W1]. *Example:* predicting the next word.\n'
        '- {{image:LSTM cell diagram|LSTM cell}} **LSTM**: adds gates. '
        '*Example: speech recognition.*\n'
        '- **Transformer** – attention only.\n';
    final blocks = parseBlocks(src);
    expect(blocks.first, isA<MdText>());
    final list = blocks[1] as MdMediaListBlock;
    expect(list.items, hasLength(3));

    final rnn = list.items[0];
    expect(rnn.number, 1);
    expect(rnn.query, 'RNN architecture diagram');
    expect(rnn.title, 'Recurrent Neural Network (RNN)');
    expect(rnn.body, 'processes one element at a time [W1].');
    expect(rnn.example, 'predicting the next word.');

    final lstm = list.items[1];
    expect(lstm.number, 2);
    expect(lstm.caption, 'LSTM cell');
    expect(lstm.title, 'LSTM');
    expect(lstm.body, 'adds gates.');
    expect(lstm.example, 'speech recognition.');

    final tf = list.items[2];
    expect(tf.query, isNull);
    expect(tf.title, 'Transformer');
    expect(tf.example, isNull);
  });

  test('ordered lists keep their numbers', () {
    const src =
        '3. {{image:Raspberry Pi 5 board}} **Raspberry Pi** - a small board.\n'
        '4. {{image:Arduino Uno}} **Arduino** - a microcontroller.\n';
    final list = parseBlocks(src).single as MdMediaListBlock;
    expect(list.items.map((i) => i.number), [3, 4]);
  });

  test('a list with few images stays a timeline list', () {
    const src =
        '- {{image:cat}} **Cat** - a pet.\n'
        '- **Step one** - do this.\n'
        '- **Step two** - do that.\n';
    expect(parseBlocks(src).single, isA<MdListBlock>());
  });

  test('an item still streaming in does not change the block kind', () {
    const src =
        '- {{image:RNN diagram}} **RNN** – sequences.\n'
        '- {{image:LSTM diagram}} **LSTM** – gates.\n'
        '- ';
    final list = parseBlocks(src).single as MdMediaListBlock;
    expect(list.items, hasLength(3));
    expect(list.items.last.title, isNull);
  });

  test('example label with nothing after it yet keeps an empty line', () {
    const src = '- {{image:GRU diagram}} **GRU** – simpler. *Example:*';
    final item = (parseBlocks(src).single as MdMediaListBlock).items.single;
    expect(item.body, 'simpler.');
    expect(item.example, '');
  });

  test('blank-line items with the example on its own line', () {
    const src =
        '## Main architectures\n\n'
        '- {{image:RNN diagram}} **Recurrent Neural Network (RNN)** – keeps a '
        'running memory.  \n'
        '  *Example:* predicting the next character.\n\n'
        '- {{image:LSTM cell diagram}} **LSTM** – adds gates.  \n'
        '  *Example:* language modelling.\n\n'
        'Bottom line.';
    final blocks = parseBlocks(src);
    final list = blocks[1] as MdMediaListBlock;
    expect(list.items, hasLength(2));
    expect(list.items.first.body, 'keeps a running memory.');
    expect(list.items.first.example, 'predicting the next character.');
    expect(list.items.last.title, 'LSTM');
    expect(blocks.last, isA<MdText>());
  });

  test('an example with code stays in the body', () {
    const src =
        '- {{image:RNN diagram}} **RNN** – steps.\n'
        '  *Example*:\n'
        '  ```python\n'
        '  rnn = nn.RNN(64, 128)\n'
        '  ```\n';
    final item = (parseBlocks(src).single as MdMediaListBlock).items.single;
    expect(item.example, isNull);
    expect(item.body, contains('```python'));
  });
}
