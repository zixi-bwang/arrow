// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package array

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"reflect"
	"sync/atomic"

	"github.com/apache/arrow/go/v7/arrow"
	"github.com/apache/arrow/go/v7/arrow/internal/debug"
	"github.com/apache/arrow/go/v7/arrow/memory"
	"github.com/goccy/go-json"
)

// A FixedSizeBinaryBuilder is used to build a FixedSizeBinary array using the Append methods.
type FixedSizeBinaryBuilder struct {
	builder

	dtype  *arrow.FixedSizeBinaryType
	values *byteBufferBuilder
}

func NewFixedSizeBinaryBuilder(mem memory.Allocator, dtype *arrow.FixedSizeBinaryType) *FixedSizeBinaryBuilder {
	b := &FixedSizeBinaryBuilder{
		builder: builder{refCount: 1, mem: mem},
		dtype:   dtype,
		values:  newByteBufferBuilder(mem),
	}
	return b
}

// Release decreases the reference count by 1.
// When the reference count goes to zero, the memory is freed.
// Release may be called simultaneously from multiple goroutines.
func (b *FixedSizeBinaryBuilder) Release() {
	debug.Assert(atomic.LoadInt64(&b.refCount) > 0, "too many releases")

	if atomic.AddInt64(&b.refCount, -1) == 0 {
		if b.nullBitmap != nil {
			b.nullBitmap.Release()
			b.nullBitmap = nil
		}
		if b.values != nil {
			b.values.Release()
			b.values = nil
		}
	}
}

func (b *FixedSizeBinaryBuilder) Append(v []byte) {
	if len(v) != b.dtype.ByteWidth {
		// TODO(alexandre): should we return an error instead?
		panic("len(v) != b.dtype.ByteWidth")
	}

	b.Reserve(1)
	b.values.Append(v)
	b.UnsafeAppendBoolToBitmap(true)
}

func (b *FixedSizeBinaryBuilder) AppendNull() {
	b.Reserve(1)
	b.values.Advance(b.dtype.ByteWidth)
	b.UnsafeAppendBoolToBitmap(false)
}

// AppendValues will append the values in the v slice. The valid slice determines which values
// in v are valid (not null). The valid slice must either be empty or be equal in length to v. If empty,
// all values in v are appended and considered valid.
func (b *FixedSizeBinaryBuilder) AppendValues(v [][]byte, valid []bool) {
	if len(v) != len(valid) && len(valid) != 0 {
		panic("len(v) != len(valid) && len(valid) != 0")
	}

	if len(v) == 0 {
		return
	}

	b.Reserve(len(v))
	for _, vv := range v {
		switch len(vv) {
		case 0:
			b.values.Advance(b.dtype.ByteWidth)
		case b.dtype.ByteWidth:
			b.values.Append(vv)
		default:
			panic(fmt.Errorf("array: invalid binary length (got=%d, want=%d)", len(vv), b.dtype.ByteWidth))
		}
	}

	b.builder.unsafeAppendBoolsToBitmap(valid, len(v))
}

func (b *FixedSizeBinaryBuilder) init(capacity int) {
	b.builder.init(capacity)
	b.values.resize(capacity * b.dtype.ByteWidth)
}

// Reserve ensures there is enough space for appending n elements
// by checking the capacity and calling Resize if necessary.
func (b *FixedSizeBinaryBuilder) Reserve(n int) {
	b.builder.reserve(n, b.Resize)
}

// Resize adjusts the space allocated by b to n elements. If n is greater than b.Cap(),
// additional memory will be allocated. If n is smaller, the allocated memory may reduced.
func (b *FixedSizeBinaryBuilder) Resize(n int) {
	b.builder.resize(n, b.init)
}

// NewArray creates a FixedSizeBinary array from the memory buffers used by the
// builder and resets the FixedSizeBinaryBuilder so it can be used to build a new array.
func (b *FixedSizeBinaryBuilder) NewArray() Interface {
	return b.NewFixedSizeBinaryArray()
}

// NewFixedSizeBinaryArray creates a FixedSizeBinary array from the memory buffers used by the builder and resets the FixedSizeBinaryBuilder
// so it can be used to build a new array.
func (b *FixedSizeBinaryBuilder) NewFixedSizeBinaryArray() (a *FixedSizeBinary) {
	data := b.newData()
	a = NewFixedSizeBinaryData(data)
	data.Release()
	return
}

func (b *FixedSizeBinaryBuilder) newData() (data *Data) {
	values := b.values.Finish()
	data = NewData(b.dtype, b.length, []*memory.Buffer{b.nullBitmap, values}, nil, b.nulls, 0)

	if values != nil {
		values.Release()
	}

	b.builder.reset()

	return
}

func (b *FixedSizeBinaryBuilder) unmarshalOne(dec *json.Decoder) error {
	t, err := dec.Token()
	if err != nil {
		return err
	}

	var val []byte
	switch v := t.(type) {
	case string:
		data, err := base64.RawStdEncoding.DecodeString(v)
		if err != nil {
			return err
		}
		val = data
	case []byte:
		val = v
	case nil:
		b.AppendNull()
		return nil
	default:
		return &json.UnmarshalTypeError{
			Value:  fmt.Sprint(t),
			Type:   reflect.TypeOf([]byte{}),
			Offset: dec.InputOffset(),
			Struct: fmt.Sprintf("FixedSizeBinary[%d]", b.dtype.ByteWidth),
		}
	}

	if len(val) != b.dtype.ByteWidth {
		return &json.UnmarshalTypeError{
			Value:  fmt.Sprint(val),
			Type:   reflect.TypeOf([]byte{}),
			Offset: dec.InputOffset(),
			Struct: fmt.Sprintf("FixedSizeBinary[%d]", b.dtype.ByteWidth),
		}
	}
	b.Append(val)
	return nil
}

func (b *FixedSizeBinaryBuilder) unmarshal(dec *json.Decoder) error {
	for dec.More() {
		if err := b.unmarshalOne(dec); err != nil {
			return err
		}
	}
	return nil
}

func (b *FixedSizeBinaryBuilder) UnmarshalJSON(data []byte) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	t, err := dec.Token()
	if err != nil {
		return err
	}

	if delim, ok := t.(json.Delim); !ok || delim != '[' {
		return fmt.Errorf("fixed size binary builder must unpack from json array, found %s", delim)
	}

	return b.unmarshal(dec)
}

var (
	_ Builder = (*FixedSizeBinaryBuilder)(nil)
)
