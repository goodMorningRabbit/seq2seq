#!/usr/bin/env bash

set -e  # exit script on failure

# set as variable before running script
if [[ -z  ${GPU} ]]
then
    echo "error: you need to set variable \$GPU"
    exit 1
fi

data_dir=data/btec_fr-en
train_dir=model/btec_fr-en
gpu_id=${GPU}
embedding_size=1024
vocab_size=10000   # greater than actual size
num_samples=512
layers=1
dropout_rate=0.5

mkdir -p ${train_dir}
mkdir -p ${data_dir}

if test "$(ls -A "${train_dir}")"; then
    read -p "warning: train dir is not empty, continue? [y/N] " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        exit 1
    fi
fi

if test "$(ls -A "${data_dir}")"; then
    echo "warning: data dir is not empty, skipping data preparation"
else

corpus_train=data/raw/btec.fr-en
corpus_dev=data/raw/btec-dev.fr-en
corpus_test=data/raw/btec-test.fr-en

echo "### pre-processing data"

./scripts/prepare-data.py ${corpus_train} fr en ${data_dir} --mode all \
--verbose \
--max 50 \
--lowercase \
--dev-corpus ${corpus_dev} \
--test-corpus ${corpus_test} \
--vocab-size ${vocab_size}
fi

echo "### training model"

export LD_LIBRARY_PATH="/usr/local/cuda/lib64/"
python -m translate ${data_dir} ${train_dir} \
--train \
--size ${embedding_size} \
--num-layers ${layers} \
--vocab-size ${vocab_size} \
--src-ext fr \
--trg-ext en \
--verbose \
--log-file ${train_dir}/log.txt \
--gpu-id ${GPU} \
--steps-per-checkpoint 1000 \
--steps-per-eval 2000 \
--dev-prefix dev \
--allow-growth \
--dropout-rate ${dropout_rate} \
--beam-size 1

exit   # rest of the script is to run by hand

## evaluation
mkdir ${train_dir}/eval
python2 -m translate ${data_dir} ${train_dir} \
--decode ${data_dir}/test --beam-size 4 --output ${train_dir}/eval/test.beam_4.out \
--reset --checkpoints ${train_dir}/checkpoints.fr_en/best \
--vocab-size ${vocab_size} --size ${embedding_size} -v

# scripts/multi-bleu.perl ${data_dir}/test.en < btec-eval/test.beam_1.out
scripts/scoring/score.rb --hyp-detok ${train_dir}/eval/test.beam_4.out --ref ${data_dir}/test.en --print

## finetuning
python2 -m translate ${data_dir} ${train_dir}_tuned/ \
--train -v \
--checkpoints ${train_dir}/checkpoints.fr_en/best \
--vocab-size ${vocab_size} --size ${embedding_size} --beam-size 1 --train-prefix train \
--steps-per-checkpoint 1000 --steps-per-eval 2000 \
--dropout-rate ${dropout_rate} \
--freeze-variables multi_encoder/encoder_fr/embedding:0 attention_decoder/embedding:0 \
--allow-growth --log-file ${train_dir}_tuned/log.txt
